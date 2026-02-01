/*
 * OBS Background Removal Plugin for macOS
 * Vision Framework Processor - Implementation
 * Copyright (C) 2026 Andreas Kuschner
 *
 * Uses Apple Vision Framework VNGeneratePersonSegmentationRequest
 * for real-time person segmentation with hardware acceleration.
 */

#import "vision-processor.h"
#import <Accelerate/Accelerate.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

@interface VisionProcessor ()

// Vision requests
@property (nonatomic, strong) VNSequenceRequestHandler *sequenceHandler;
@property (nonatomic, strong) VNGeneratePersonSegmentationRequest *segmentationRequest;

// Metal resources for GPU acceleration
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CIContext *ciContext;

// Temporal smoothing state
@property (nonatomic, strong) CIImage *previousMask;
@property (nonatomic, assign) NSUInteger internalFrameCount;
@property (nonatomic, assign) double totalProcessingTime;

// Pixel buffer pool for output
@property (nonatomic, assign) CVPixelBufferPoolRef outputPool;
@property (nonatomic, assign) CGSize lastInputSize;

@end

@implementation VisionProcessor

#pragma mark - Initialization

- (instancetype)init
{
    return [self initWithQuality:SegmentationQualityBalanced];
}

- (instancetype)initWithQuality:(SegmentationQuality)quality
{
    self = [super init];
    if (self) {
        _quality = quality;
        _backgroundMode = BackgroundModeBlur;
        _blurRadius = 20.0f;
        _edgeSmoothing = 1.0f;
        _maskThreshold = 0.5f;
        _backgroundColor = [CIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0]; // Green screen
        _temporalSmoothing = YES;
        _temporalSmoothingFactor = 0.8f;
        _edgeRefinement = YES;
        _lastInputSize = CGSizeZero;

        [self setupMetal];
        [self setupVision];
    }
    return self;
}

- (void)dealloc
{
    [self invalidate];
}

#pragma mark - Setup

- (void)setupMetal
{
    // Get the default Metal device (Apple Silicon GPU)
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (!_metalDevice) {
        NSLog(@"[Background Removal] Failed to create Metal device, falling back to CPU");
        _ciContext = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO
        }];
        return;
    }

    _commandQueue = [_metalDevice newCommandQueue];

    // Create CIContext with Metal for GPU-accelerated image processing
    _ciContext = [CIContext contextWithMTLDevice:_metalDevice options:@{
        kCIContextWorkingColorSpace: (__bridge id)CGColorSpaceCreateDeviceRGB(),
        kCIContextHighQualityDownsample: @YES,
        kCIContextPriorityRequestLow: @NO,
        kCIContextCacheIntermediates: @YES
    }];

    NSLog(@"[Background Removal] Metal GPU acceleration enabled: %@", _metalDevice.name);
}

- (void)setupVision
{
    // Create the person segmentation request
    _segmentationRequest = [[VNGeneratePersonSegmentationRequest alloc] init];

    // Set quality level
    switch (_quality) {
        case SegmentationQualityFast:
            _segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelFast;
            break;
        case SegmentationQualityBalanced:
            _segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
            break;
        case SegmentationQualityAccurate:
            _segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
            break;
    }

    // Output single-channel float mask
    _segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent32Float;

    // Create sequence handler for temporal consistency
    _sequenceHandler = [[VNSequenceRequestHandler alloc] init];

    NSLog(@"[Background Removal] Vision Framework initialized with quality: %ld", (long)_quality);
}

#pragma mark - Quality Configuration

- (void)setQuality:(SegmentationQuality)quality
{
    if (_quality != quality) {
        _quality = quality;

        switch (quality) {
            case SegmentationQualityFast:
                _segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelFast;
                break;
            case SegmentationQualityBalanced:
                _segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
                break;
            case SegmentationQualityAccurate:
                _segmentationRequest.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
                break;
        }

        NSLog(@"[Background Removal] Quality changed to: %ld", (long)quality);
    }
}

#pragma mark - Processing

- (CVPixelBufferRef)processPixelBuffer:(CVPixelBufferRef)inputBuffer
{
    return [self processPixelBuffer:inputBuffer withBackground:nil];
}

- (CVPixelBufferRef)processPixelBuffer:(CVPixelBufferRef)inputBuffer
                        withBackground:(CVPixelBufferRef)backgroundBuffer
{
    if (!inputBuffer) {
        return NULL;
    }

    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

    // Get input dimensions
    size_t width = CVPixelBufferGetWidth(inputBuffer);
    size_t height = CVPixelBufferGetHeight(inputBuffer);
    CGSize inputSize = CGSizeMake(width, height);

    // Create output pixel buffer pool if needed
    if (!CGSizeEqualToSize(_lastInputSize, inputSize)) {
        [self createOutputPoolForSize:inputSize];
        _lastInputSize = inputSize;
    }

    // Perform person segmentation
    NSError *error = nil;
    [_sequenceHandler performRequests:@[_segmentationRequest]
                        onCVPixelBuffer:inputBuffer
                                  error:&error];

    if (error) {
        NSLog(@"[Background Removal] Segmentation error: %@", error.localizedDescription);
        CVPixelBufferRetain(inputBuffer);
        return inputBuffer;
    }

    // Get the segmentation mask
    VNPixelBufferObservation *maskObservation = _segmentationRequest.results.firstObject;
    if (!maskObservation) {
        CVPixelBufferRetain(inputBuffer);
        return inputBuffer;
    }

    CVPixelBufferRef maskBuffer = maskObservation.pixelBuffer;

    // Process the frame with the mask
    CVPixelBufferRef outputBuffer = [self compositeFrame:inputBuffer
                                               withMask:maskBuffer
                                             background:backgroundBuffer];

    // Update performance metrics
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    _lastProcessingTime = (endTime - startTime) * 1000.0; // Convert to ms
    _totalProcessingTime += _lastProcessingTime;
    _internalFrameCount++;
    _averageProcessingTime = _totalProcessingTime / _internalFrameCount;

    return outputBuffer;
}

- (CVPixelBufferRef)compositeFrame:(CVPixelBufferRef)inputBuffer
                          withMask:(CVPixelBufferRef)maskBuffer
                        background:(CVPixelBufferRef)backgroundBuffer
{
    // Create CIImages
    CIImage *inputImage = [CIImage imageWithCVPixelBuffer:inputBuffer];
    CIImage *maskImage = [CIImage imageWithCVPixelBuffer:maskBuffer];

    // Scale mask to match input size
    CGRect inputExtent = inputImage.extent;
    CGRect maskExtent = maskImage.extent;

    CGFloat scaleX = inputExtent.size.width / maskExtent.size.width;
    CGFloat scaleY = inputExtent.size.height / maskExtent.size.height;

    maskImage = [maskImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];

    // Apply edge smoothing
    if (_edgeSmoothing > 0) {
        CIFilter *blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
        [blurFilter setValue:maskImage forKey:kCIInputImageKey];
        [blurFilter setValue:@(_edgeSmoothing) forKey:kCIInputRadiusKey];
        maskImage = blurFilter.outputImage;
    }

    // Apply mask threshold
    if (_maskThreshold != 0.5f) {
        CIFilter *clampFilter = [CIFilter filterWithName:@"CIColorClamp"];
        [clampFilter setValue:maskImage forKey:kCIInputImageKey];
        [clampFilter setValue:[CIVector vectorWithX:_maskThreshold Y:0 Z:0 W:0] forKey:@"inputMinComponents"];
        [clampFilter setValue:[CIVector vectorWithX:1 Y:1 Z:1 W:1] forKey:@"inputMaxComponents"];
        maskImage = clampFilter.outputImage;
    }

    // Apply temporal smoothing
    if (_temporalSmoothing && _previousMask) {
        CIFilter *blendFilter = [CIFilter filterWithName:@"CISourceOverCompositing"];

        // Multiply current mask by factor
        CIFilter *currentMultiply = [CIFilter filterWithName:@"CIColorMatrix"];
        [currentMultiply setValue:maskImage forKey:kCIInputImageKey];
        CGFloat currentFactor = 1.0f - _temporalSmoothingFactor;
        [currentMultiply setValue:[CIVector vectorWithX:currentFactor Y:0 Z:0 W:0] forKey:@"inputRVector"];
        [currentMultiply setValue:[CIVector vectorWithX:0 Y:currentFactor Z:0 W:0] forKey:@"inputGVector"];
        [currentMultiply setValue:[CIVector vectorWithX:0 Y:0 Z:currentFactor W:0] forKey:@"inputBVector"];
        [currentMultiply setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
        CIImage *scaledCurrent = currentMultiply.outputImage;

        // Multiply previous mask by temporal factor
        CIFilter *prevMultiply = [CIFilter filterWithName:@"CIColorMatrix"];
        [prevMultiply setValue:_previousMask forKey:kCIInputImageKey];
        [prevMultiply setValue:[CIVector vectorWithX:_temporalSmoothingFactor Y:0 Z:0 W:0] forKey:@"inputRVector"];
        [prevMultiply setValue:[CIVector vectorWithX:0 Y:_temporalSmoothingFactor Z:0 W:0] forKey:@"inputGVector"];
        [prevMultiply setValue:[CIVector vectorWithX:0 Y:0 Z:_temporalSmoothingFactor W:0] forKey:@"inputBVector"];
        [prevMultiply setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
        CIImage *scaledPrev = prevMultiply.outputImage;

        // Add together
        CIFilter *addFilter = [CIFilter filterWithName:@"CIAdditionCompositing"];
        [addFilter setValue:scaledCurrent forKey:kCIInputImageKey];
        [addFilter setValue:scaledPrev forKey:kCIInputBackgroundImageKey];
        maskImage = addFilter.outputImage;
    }

    // Store mask for next frame
    _previousMask = maskImage;

    // Create background image based on mode
    CIImage *backgroundImage = nil;

    switch (_backgroundMode) {
        case BackgroundModeBlur: {
            CIFilter *blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
            [blurFilter setValue:inputImage forKey:kCIInputImageKey];
            [blurFilter setValue:@(_blurRadius) forKey:kCIInputRadiusKey];
            backgroundImage = blurFilter.outputImage;

            // Clamp to prevent edge artifacts from blur
            backgroundImage = [backgroundImage imageByCroppingToRect:inputExtent];
            break;
        }

        case BackgroundModeColor: {
            backgroundImage = [CIImage imageWithColor:_backgroundColor];
            backgroundImage = [backgroundImage imageByCroppingToRect:inputExtent];
            break;
        }

        case BackgroundModeTransparent: {
            // Create transparent background
            backgroundImage = [CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:0]];
            backgroundImage = [backgroundImage imageByCroppingToRect:inputExtent];
            break;
        }

        case BackgroundModeImage: {
            if (backgroundBuffer) {
                backgroundImage = [CIImage imageWithCVPixelBuffer:backgroundBuffer];
                // Scale to match input size
                CGRect bgExtent = backgroundImage.extent;
                CGFloat bgScaleX = inputExtent.size.width / bgExtent.size.width;
                CGFloat bgScaleY = inputExtent.size.height / bgExtent.size.height;
                backgroundImage = [backgroundImage imageByApplyingTransform:
                                   CGAffineTransformMakeScale(bgScaleX, bgScaleY)];
            } else {
                // Fallback to blur if no background image
                CIFilter *blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
                [blurFilter setValue:inputImage forKey:kCIInputImageKey];
                [blurFilter setValue:@(_blurRadius) forKey:kCIInputRadiusKey];
                backgroundImage = blurFilter.outputImage;
                backgroundImage = [backgroundImage imageByCroppingToRect:inputExtent];
            }
            break;
        }
    }

    // Composite: blend foreground (person) over background using mask
    CIFilter *blendFilter = [CIFilter filterWithName:@"CIBlendWithMask"];
    [blendFilter setValue:backgroundImage forKey:kCIInputBackgroundImageKey];
    [blendFilter setValue:inputImage forKey:kCIInputImageKey];
    [blendFilter setValue:maskImage forKey:kCIInputMaskImageKey];

    CIImage *outputImage = blendFilter.outputImage;

    // Crop to original bounds
    outputImage = [outputImage imageByCroppingToRect:inputExtent];

    // Render to output pixel buffer
    CVPixelBufferRef outputBuffer = NULL;
    CVReturn status = CVPixelBufferPoolCreatePixelBuffer(NULL, _outputPool, &outputBuffer);
    if (status != kCVReturnSuccess) {
        NSLog(@"[Background Removal] Failed to create output buffer: %d", status);
        CVPixelBufferRetain(inputBuffer);
        return inputBuffer;
    }

    [_ciContext render:outputImage toCVPixelBuffer:outputBuffer];

    return outputBuffer;
}

#pragma mark - Pixel Buffer Pool

- (void)createOutputPoolForSize:(CGSize)size
{
    if (_outputPool) {
        CVPixelBufferPoolRelease(_outputPool);
        _outputPool = NULL;
    }

    NSDictionary *poolAttributes = @{
        (NSString *)kCVPixelBufferPoolMinimumBufferCountKey: @3
    };

    NSDictionary *pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferWidthKey: @((int)size.width),
        (NSString *)kCVPixelBufferHeightKey: @((int)size.height),
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES
    };

    CVReturn status = CVPixelBufferPoolCreate(
        kCFAllocatorDefault,
        (__bridge CFDictionaryRef)poolAttributes,
        (__bridge CFDictionaryRef)pixelBufferAttributes,
        &_outputPool
    );

    if (status != kCVReturnSuccess) {
        NSLog(@"[Background Removal] Failed to create pixel buffer pool: %d", status);
    }
}

#pragma mark - Performance Metrics

- (NSUInteger)frameCount
{
    return _internalFrameCount;
}

#pragma mark - Cleanup

- (void)reset
{
    _previousMask = nil;
    _internalFrameCount = 0;
    _totalProcessingTime = 0;
    _lastProcessingTime = 0;
    _averageProcessingTime = 0;

    // Reset sequence handler for fresh temporal state
    _sequenceHandler = [[VNSequenceRequestHandler alloc] init];
}

- (void)invalidate
{
    [self reset];

    if (_outputPool) {
        CVPixelBufferPoolRelease(_outputPool);
        _outputPool = NULL;
    }

    _metalDevice = nil;
    _commandQueue = nil;
    _ciContext = nil;
    _segmentationRequest = nil;
    _sequenceHandler = nil;
}

@end
