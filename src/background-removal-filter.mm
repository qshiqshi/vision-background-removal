/*
 * OBS Background Removal Plugin for macOS
 * Video Filter Implementation
 * Copyright (C) 2026 Andreas Kuschner
 */

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>

extern "C" {
#include <obs-module.h>
#include <graphics/graphics.h>
#include <graphics/vec4.h>
}

#include "background-removal-filter.h"

// Filter data structure - use void* for ObjC objects to manage manually
struct background_removal_filter_data {
    obs_source_t *source;

    // Settings
    bool enabled;
    int background_mode;
    int blur_radius;
    float smoothing;
    uint32_t bg_color;

    // Graphics resources
    gs_texrender_t *texrender;
    gs_stagesurf_t *stagesurface;
    gs_texture_t *output_texture;
    uint32_t width;
    uint32_t height;

    // Vision Framework (stored as void* with manual retain/release)
    void *sequenceHandler;      // VNSequenceRequestHandler
    void *segmentationRequest;  // VNGeneratePersonSegmentationRequest
    void *ciContext;            // CIContext

    // Pixel buffer pool
    CVPixelBufferPoolRef bufferPool;
};

#pragma mark - Forward Declarations

static const char *filter_get_name(void *unused);
static void *filter_create(obs_data_t *settings, obs_source_t *source);
static void filter_destroy(void *data);
static void filter_update(void *data, obs_data_t *settings);
static obs_properties_t *filter_get_properties(void *data);
static void filter_get_defaults(obs_data_t *settings);
static void filter_video_render(void *data, gs_effect_t *effect);
static void filter_video_tick(void *data, float seconds);

#pragma mark - Source Info Definition

struct obs_source_info background_removal_filter_info = {
    .id = "vision_background_removal_filter",
    .type = OBS_SOURCE_TYPE_FILTER,
    .output_flags = OBS_SOURCE_VIDEO,
    .get_name = filter_get_name,
    .create = filter_create,
    .destroy = filter_destroy,
    .update = filter_update,
    .get_properties = filter_get_properties,
    .get_defaults = filter_get_defaults,
    .video_render = filter_video_render,
    .video_tick = filter_video_tick,
};

#pragma mark - Helper Functions

static void create_buffer_pool(struct background_removal_filter_data *filter, uint32_t width, uint32_t height)
{
    @autoreleasepool {
        if (filter->bufferPool) {
            CVPixelBufferPoolRelease(filter->bufferPool);
            filter->bufferPool = NULL;
        }

        NSDictionary *poolAttrs = @{
            (NSString *)kCVPixelBufferPoolMinimumBufferCountKey: @3
        };

        NSDictionary *pixelAttrs = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (NSString *)kCVPixelBufferWidthKey: @(width),
            (NSString *)kCVPixelBufferHeightKey: @(height),
            (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };

        CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                (__bridge CFDictionaryRef)poolAttrs,
                                (__bridge CFDictionaryRef)pixelAttrs,
                                &filter->bufferPool);
    }
}

#pragma mark - Filter Callbacks

static const char *filter_get_name(void *unused)
{
    UNUSED_PARAMETER(unused);
    return "Vision Background Removal";
}

static void *filter_create(obs_data_t *settings, obs_source_t *source)
{
    struct background_removal_filter_data *filter =
        (struct background_removal_filter_data *)bzalloc(sizeof(*filter));

    filter->source = source;
    filter->enabled = true;
    filter->background_mode = BG_MODE_BLUR;
    filter->blur_radius = 20;
    filter->smoothing = 1.0f;
    filter->bg_color = 0xFF00FF00; // Green
    filter->width = 0;
    filter->height = 0;

    @autoreleasepool {
        // Create and retain Vision request
        VNGeneratePersonSegmentationRequest *req = [[VNGeneratePersonSegmentationRequest alloc] init];
        req.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8;
        filter->segmentationRequest = (void *)CFBridgingRetain(req);

        // Create and retain sequence handler
        VNSequenceRequestHandler *handler = [[VNSequenceRequestHandler alloc] init];
        filter->sequenceHandler = (void *)CFBridgingRetain(handler);

        // Create and retain CIContext with Metal
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        CIContext *ctx;
        if (device) {
            ctx = [CIContext contextWithMTLDevice:device];
        } else {
            ctx = [CIContext context];
        }
        filter->ciContext = (void *)CFBridgingRetain(ctx);
    }

    filter_update(filter, settings);

    blog(LOG_INFO, "[Vision Background Removal] Filter created");

    return filter;
}

static void filter_destroy(void *data)
{
    struct background_removal_filter_data *filter =
        (struct background_removal_filter_data *)data;

    if (!filter) return;

    blog(LOG_INFO, "[Vision Background Removal] Destroying filter...");

    obs_enter_graphics();

    if (filter->texrender) {
        gs_texrender_destroy(filter->texrender);
        filter->texrender = NULL;
    }
    if (filter->stagesurface) {
        gs_stagesurface_destroy(filter->stagesurface);
        filter->stagesurface = NULL;
    }
    if (filter->output_texture) {
        gs_texture_destroy(filter->output_texture);
        filter->output_texture = NULL;
    }

    obs_leave_graphics();

    if (filter->bufferPool) {
        CVPixelBufferPoolRelease(filter->bufferPool);
        filter->bufferPool = NULL;
    }

    // Release ObjC objects
    if (filter->segmentationRequest) {
        CFBridgingRelease(filter->segmentationRequest);
        filter->segmentationRequest = NULL;
    }
    if (filter->sequenceHandler) {
        CFBridgingRelease(filter->sequenceHandler);
        filter->sequenceHandler = NULL;
    }
    if (filter->ciContext) {
        CFBridgingRelease(filter->ciContext);
        filter->ciContext = NULL;
    }

    bfree(filter);

    blog(LOG_INFO, "[Vision Background Removal] Filter destroyed");
}

static void filter_update(void *data, obs_data_t *settings)
{
    struct background_removal_filter_data *filter =
        (struct background_removal_filter_data *)data;

    if (!filter) return;

    filter->enabled = obs_data_get_bool(settings, "enabled");
    filter->background_mode = (int)obs_data_get_int(settings, "background_mode");
    filter->blur_radius = (int)obs_data_get_int(settings, "blur_radius");
    filter->smoothing = (float)obs_data_get_double(settings, "smoothing");
    filter->bg_color = (uint32_t)obs_data_get_int(settings, "bg_color");

    int quality = (int)obs_data_get_int(settings, "quality");

    @autoreleasepool {
        VNGeneratePersonSegmentationRequest *req =
            (__bridge VNGeneratePersonSegmentationRequest *)filter->segmentationRequest;
        if (req) {
            switch (quality) {
                case 0:
                    req.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelFast;
                    break;
                case 1:
                    req.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
                    break;
                case 2:
                    req.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
                    break;
            }
        }
    }
}

static obs_properties_t *filter_get_properties(void *data)
{
    UNUSED_PARAMETER(data);

    obs_properties_t *props = obs_properties_create();

    obs_properties_add_bool(props, "enabled", "Enable");

    obs_property_t *quality = obs_properties_add_list(props, "quality", "Quality",
        OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_INT);
    obs_property_list_add_int(quality, "Fast", 0);
    obs_property_list_add_int(quality, "Balanced", 1);
    obs_property_list_add_int(quality, "Accurate", 2);

    obs_property_t *bg_mode = obs_properties_add_list(props, "background_mode", "Background",
        OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_INT);
    obs_property_list_add_int(bg_mode, "Blur", BG_MODE_BLUR);
    obs_property_list_add_int(bg_mode, "Solid Color", BG_MODE_COLOR);
    obs_property_list_add_int(bg_mode, "Transparent", BG_MODE_TRANSPARENT);

    obs_properties_add_int_slider(props, "blur_radius", "Blur Radius", 5, 50, 1);
    obs_properties_add_color(props, "bg_color", "Background Color");
    obs_properties_add_float_slider(props, "smoothing", "Edge Smoothing", 0.0, 5.0, 0.1);

    return props;
}

static void filter_get_defaults(obs_data_t *settings)
{
    obs_data_set_default_bool(settings, "enabled", true);
    obs_data_set_default_int(settings, "quality", 1);
    obs_data_set_default_int(settings, "background_mode", BG_MODE_BLUR);
    obs_data_set_default_int(settings, "blur_radius", 20);
    obs_data_set_default_int(settings, "bg_color", 0xFF00FF00);
    obs_data_set_default_double(settings, "smoothing", 1.0);
}

static void filter_video_tick(void *data, float seconds)
{
    UNUSED_PARAMETER(seconds);

    struct background_removal_filter_data *filter =
        (struct background_removal_filter_data *)data;

    if (!filter) return;

    obs_source_t *target = obs_filter_get_target(filter->source);
    if (!target) return;

    uint32_t width = obs_source_get_base_width(target);
    uint32_t height = obs_source_get_base_height(target);

    if (width == 0 || height == 0) return;

    if (filter->width != width || filter->height != height) {
        filter->width = width;
        filter->height = height;

        obs_enter_graphics();

        if (filter->texrender) {
            gs_texrender_destroy(filter->texrender);
        }
        filter->texrender = gs_texrender_create(GS_BGRA, GS_ZS_NONE);

        if (filter->stagesurface) {
            gs_stagesurface_destroy(filter->stagesurface);
        }
        filter->stagesurface = gs_stagesurface_create(width, height, GS_BGRA);

        if (filter->output_texture) {
            gs_texture_destroy(filter->output_texture);
            filter->output_texture = NULL;
        }

        obs_leave_graphics();

        create_buffer_pool(filter, width, height);

        blog(LOG_INFO, "[Vision Background Removal] Resized to %ux%u", width, height);
    }
}

static void filter_video_render(void *data, gs_effect_t *effect)
{
    UNUSED_PARAMETER(effect);

    struct background_removal_filter_data *filter =
        (struct background_removal_filter_data *)data;

    if (!filter) return;

    obs_source_t *target = obs_filter_get_target(filter->source);
    if (!target) {
        obs_source_skip_video_filter(filter->source);
        return;
    }

    // Skip if not ready
    if (!filter->enabled || !filter->texrender || !filter->stagesurface ||
        filter->width == 0 || filter->height == 0 || !filter->bufferPool ||
        !filter->sequenceHandler || !filter->segmentationRequest || !filter->ciContext) {
        obs_source_skip_video_filter(filter->source);
        return;
    }

    // Render source to texture
    gs_texrender_reset(filter->texrender);
    if (!gs_texrender_begin(filter->texrender, filter->width, filter->height)) {
        obs_source_skip_video_filter(filter->source);
        return;
    }

    struct vec4 clear_color;
    vec4_zero(&clear_color);
    gs_clear(GS_CLEAR_COLOR, &clear_color, 0.0f, 0);
    gs_ortho(0.0f, (float)filter->width, 0.0f, (float)filter->height, -100.0f, 100.0f);

    obs_source_video_render(target);
    gs_texrender_end(filter->texrender);

    gs_texture_t *source_texture = gs_texrender_get_texture(filter->texrender);
    if (!source_texture) {
        obs_source_skip_video_filter(filter->source);
        return;
    }

    // Stage texture for CPU access
    gs_stage_texture(filter->stagesurface, source_texture);

    uint8_t *stageData;
    uint32_t linesize;
    if (!gs_stagesurface_map(filter->stagesurface, &stageData, &linesize)) {
        obs_source_skip_video_filter(filter->source);
        return;
    }

    @autoreleasepool {
        // Get pixel buffer from pool
        CVPixelBufferRef inputBuffer = NULL;
        CVReturn status = CVPixelBufferPoolCreatePixelBuffer(NULL, filter->bufferPool, &inputBuffer);
        if (status != kCVReturnSuccess || !inputBuffer) {
            gs_stagesurface_unmap(filter->stagesurface);
            obs_source_skip_video_filter(filter->source);
            return;
        }

        // Copy frame data to pixel buffer
        CVPixelBufferLockBaseAddress(inputBuffer, 0);
        uint8_t *dstData = (uint8_t *)CVPixelBufferGetBaseAddress(inputBuffer);
        size_t dstBytesPerRow = CVPixelBufferGetBytesPerRow(inputBuffer);
        size_t copyBytes = MIN((size_t)linesize, dstBytesPerRow);

        for (uint32_t y = 0; y < filter->height; y++) {
            memcpy(dstData + y * dstBytesPerRow, stageData + y * linesize, copyBytes);
        }
        CVPixelBufferUnlockBaseAddress(inputBuffer, 0);
        gs_stagesurface_unmap(filter->stagesurface);

        // Get ObjC objects via __bridge (no ownership transfer)
        VNSequenceRequestHandler *handler = (__bridge VNSequenceRequestHandler *)filter->sequenceHandler;
        VNGeneratePersonSegmentationRequest *req = (__bridge VNGeneratePersonSegmentationRequest *)filter->segmentationRequest;
        CIContext *ciCtx = (__bridge CIContext *)filter->ciContext;

        // Perform segmentation
        NSError *error = nil;
        BOOL success = [handler performRequests:@[req] onCVPixelBuffer:inputBuffer error:&error];

        if (!success || error || req.results.count == 0) {
            CVPixelBufferRelease(inputBuffer);
            obs_source_skip_video_filter(filter->source);
            return;
        }

        VNPixelBufferObservation *maskObs = req.results.firstObject;
        if (!maskObs || !maskObs.pixelBuffer) {
            CVPixelBufferRelease(inputBuffer);
            obs_source_skip_video_filter(filter->source);
            return;
        }

        CVPixelBufferRef maskBuffer = maskObs.pixelBuffer;

        // Create CIImages
        CIImage *inputImage = [CIImage imageWithCVPixelBuffer:inputBuffer];
        CIImage *maskImage = [CIImage imageWithCVPixelBuffer:maskBuffer];

        if (!inputImage || !maskImage) {
            CVPixelBufferRelease(inputBuffer);
            obs_source_skip_video_filter(filter->source);
            return;
        }

        // Scale mask to input size
        CGFloat scaleX = (CGFloat)filter->width / maskImage.extent.size.width;
        CGFloat scaleY = (CGFloat)filter->height / maskImage.extent.size.height;
        maskImage = [maskImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];

        // Smooth mask edges
        if (filter->smoothing > 0.1f) {
            CIFilter *maskBlur = [CIFilter filterWithName:@"CIGaussianBlur"];
            [maskBlur setValue:maskImage forKey:kCIInputImageKey];
            [maskBlur setValue:@(filter->smoothing) forKey:kCIInputRadiusKey];
            CIImage *blurredMask = maskBlur.outputImage;
            if (blurredMask) {
                maskImage = blurredMask;
            }
        }

        CIImage *outputImage = nil;

        switch (filter->background_mode) {
            case BG_MODE_BLUR: {
                // Create blurred background
                CIFilter *bgBlur = [CIFilter filterWithName:@"CIGaussianBlur"];
                [bgBlur setValue:inputImage forKey:kCIInputImageKey];
                [bgBlur setValue:@(filter->blur_radius) forKey:kCIInputRadiusKey];
                CIImage *blurredBg = bgBlur.outputImage;
                if (!blurredBg) {
                    CVPixelBufferRelease(inputBuffer);
                    obs_source_skip_video_filter(filter->source);
                    return;
                }
                blurredBg = [blurredBg imageByCroppingToRect:inputImage.extent];

                // Blend foreground over blurred background using mask
                CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
                [blend setValue:blurredBg forKey:kCIInputBackgroundImageKey];
                [blend setValue:inputImage forKey:kCIInputImageKey];
                [blend setValue:maskImage forKey:kCIInputMaskImageKey];
                outputImage = blend.outputImage;
                break;
            }

            case BG_MODE_TRANSPARENT: {
                // Blend with transparent background using mask
                CIImage *transparentBg = [CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:0]];
                transparentBg = [transparentBg imageByCroppingToRect:inputImage.extent];

                CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
                [blend setValue:transparentBg forKey:kCIInputBackgroundImageKey];
                [blend setValue:inputImage forKey:kCIInputImageKey];
                [blend setValue:maskImage forKey:kCIInputMaskImageKey];
                outputImage = blend.outputImage;
                break;
            }

            case BG_MODE_COLOR: {
                // Create solid color background
                uint8_t r = (filter->bg_color >> 16) & 0xFF;
                uint8_t g = (filter->bg_color >> 8) & 0xFF;
                uint8_t b = (filter->bg_color >> 0) & 0xFF;
                CIImage *colorBg = [CIImage imageWithColor:[CIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0]];
                colorBg = [colorBg imageByCroppingToRect:inputImage.extent];

                // Blend foreground over color background using mask
                CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
                [blend setValue:colorBg forKey:kCIInputBackgroundImageKey];
                [blend setValue:inputImage forKey:kCIInputImageKey];
                [blend setValue:maskImage forKey:kCIInputMaskImageKey];
                outputImage = blend.outputImage;
                break;
            }
        }

        if (!outputImage) {
            CVPixelBufferRelease(inputBuffer);
            obs_source_skip_video_filter(filter->source);
            return;
        }
        outputImage = [outputImage imageByCroppingToRect:inputImage.extent];

        // Get output buffer
        CVPixelBufferRef outputBuffer = NULL;
        status = CVPixelBufferPoolCreatePixelBuffer(NULL, filter->bufferPool, &outputBuffer);
        if (status != kCVReturnSuccess || !outputBuffer) {
            CVPixelBufferRelease(inputBuffer);
            obs_source_skip_video_filter(filter->source);
            return;
        }

        // Render to output buffer
        [ciCtx render:outputImage toCVPixelBuffer:outputBuffer];

        // Create texture from output
        CVPixelBufferLockBaseAddress(outputBuffer, kCVPixelBufferLock_ReadOnly);
        uint8_t *outData = (uint8_t *)CVPixelBufferGetBaseAddress(outputBuffer);

        if (filter->output_texture) {
            gs_texture_destroy(filter->output_texture);
            filter->output_texture = NULL;
        }

        if (outData) {
            filter->output_texture = gs_texture_create(filter->width, filter->height,
                                                        GS_BGRA, 1,
                                                        (const uint8_t **)&outData, 0);
        }

        CVPixelBufferUnlockBaseAddress(outputBuffer, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferRelease(outputBuffer);
        CVPixelBufferRelease(inputBuffer);
    }

    // Render output texture
    gs_texture_t *renderTex = filter->output_texture ? filter->output_texture : source_texture;

    gs_effect_t *defaultEffect = obs_get_base_effect(OBS_EFFECT_DEFAULT);
    gs_technique_t *tech = gs_effect_get_technique(defaultEffect, "Draw");
    gs_eparam_t *param = gs_effect_get_param_by_name(defaultEffect, "image");

    gs_effect_set_texture(param, renderTex);

    gs_technique_begin(tech);
    gs_technique_begin_pass(tech, 0);
    gs_draw_sprite(renderTex, 0, filter->width, filter->height);
    gs_technique_end_pass(tech);
    gs_technique_end(tech);
}
