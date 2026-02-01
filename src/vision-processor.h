/*
 * OBS Background Removal Plugin for macOS
 * Vision Framework Processor
 * Copyright (C) 2026 Andreas Kuschner
 */

#ifndef VISION_PROCESSOR_H
#define VISION_PROCESSOR_H

#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>

// Quality levels for segmentation
typedef NS_ENUM(NSInteger, SegmentationQuality) {
    SegmentationQualityFast = 0,      // ~60fps, lower quality edges
    SegmentationQualityBalanced = 1,  // ~30fps, good balance
    SegmentationQualityAccurate = 2   // ~15fps, best edge quality
};

// Background modes
typedef NS_ENUM(NSInteger, BackgroundMode) {
    BackgroundModeBlur = 0,           // Blur the background
    BackgroundModeColor = 1,          // Solid color (for chroma key)
    BackgroundModeTransparent = 2,    // Transparent (requires alpha source)
    BackgroundModeImage = 3           // Custom image replacement
};

@interface VisionProcessor : NSObject

// Configuration
@property (nonatomic, assign) SegmentationQuality quality;
@property (nonatomic, assign) BackgroundMode backgroundMode;
@property (nonatomic, assign) float blurRadius;
@property (nonatomic, assign) float edgeSmoothing;
@property (nonatomic, assign) float maskThreshold;
@property (nonatomic, strong) CIColor *backgroundColor;
@property (nonatomic, assign) BOOL temporalSmoothing;
@property (nonatomic, assign) float temporalSmoothingFactor;
@property (nonatomic, assign) BOOL edgeRefinement;

// Performance metrics
@property (nonatomic, readonly) double lastProcessingTime;
@property (nonatomic, readonly) double averageProcessingTime;
@property (nonatomic, readonly) NSUInteger frameCount;

// Initialization
- (instancetype)init;
- (instancetype)initWithQuality:(SegmentationQuality)quality;

// Processing
- (CVPixelBufferRef)processPixelBuffer:(CVPixelBufferRef)inputBuffer;
- (CVPixelBufferRef)processPixelBuffer:(CVPixelBufferRef)inputBuffer
                        withBackground:(CVPixelBufferRef)backgroundBuffer;

// Cleanup
- (void)reset;
- (void)invalidate;

@end

#endif // VISION_PROCESSOR_H
