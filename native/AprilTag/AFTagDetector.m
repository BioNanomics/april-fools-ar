#import "AFTagDetector.h"
#import "AFTagCore.h"
#include <limits.h>
#include <stdlib.h>

@interface AFTagDetector () {
    AFTagCore *_core;
    uint8_t *_gray;
    size_t _grayCapacity;
}
@property (nonatomic, strong, readwrite, nullable) NSError *lastError;
@end

@implementation AFTagDetector
- (instancetype)init {
    self = [super init];
    if (self) _core = AFTagCoreCreate();
    return self;
}
- (void)dealloc { AFTagCoreDestroy(_core); free(_gray); }
+ (NSString *)upstreamRevision { return [NSString stringWithUTF8String:AFTagCoreUpstreamRevision()]; }
- (NSArray<NSDictionary<NSString *, id> *> *)fail:(NSString *)message {
    self.lastError = [NSError errorWithDomain:@"AprilFoolsAR.AprilTag" code:1
                                    userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}
- (NSArray<NSDictionary<NSString *, id> *> *)detectPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    return [self detectPixelBuffer:pixelBuffer intrinsics:nil tagSizeMeters:0];
}
- (NSArray<NSDictionary<NSString *, id> *> *)detectPixelBuffer:(CVPixelBufferRef)pixelBuffer
    intrinsics:(NSArray<NSNumber *> *)intrinsics tagSizeMeters:(double)tagSizeMeters {
    @synchronized (self) {
        self.lastError = nil;
        if (!_core || !pixelBuffer) return [self fail:@"AprilTag detector or pixel buffer is unavailable."];
        if (CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess)
            return [self fail:@"Unable to lock the captured pixel buffer."];
        NSArray<NSDictionary<NSString *, id> *> *result = nil;
        @try {
            size_t width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer);
            size_t stride = 0;
            const uint8_t *gray = NULL;
            OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
            if (CVPixelBufferIsPlanar(pixelBuffer) &&
                (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                 format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) &&
                CVPixelBufferGetPlaneCount(pixelBuffer) >= 1) {
                width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
                height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
                stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
                gray = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            } else if (!CVPixelBufferIsPlanar(pixelBuffer) && format == kCVPixelFormatType_OneComponent8) {
                stride = CVPixelBufferGetBytesPerRow(pixelBuffer);
                gray = CVPixelBufferGetBaseAddress(pixelBuffer);
            } else if (!CVPixelBufferIsPlanar(pixelBuffer) && format == kCVPixelFormatType_32BGRA &&
                       width <= INT_MAX && height <= INT_MAX && width > 0 && height <= SIZE_MAX / width &&
                       width <= SIZE_MAX / 4 && CVPixelBufferGetBytesPerRow(pixelBuffer) >= width * 4) {
                size_t required = width * height;
                if (required > _grayCapacity) {
                    uint8_t *replacement = realloc(_gray, required);
                    if (!replacement) return [self fail:@"Unable to allocate AprilTag grayscale scratch memory."];
                    _gray = replacement; _grayCapacity = required;
                }
                const uint8_t *pixels = CVPixelBufferGetBaseAddress(pixelBuffer);
                if (!pixels) return [self fail:@"Captured BGRA pixel buffer has no storage."];
                size_t sourceStride = CVPixelBufferGetBytesPerRow(pixelBuffer);
                for (size_t y = 0; y < height; y++) {
                    const uint8_t *row = pixels + y * sourceStride;
                    uint8_t *target = _gray + y * width;
                    for (size_t x = 0; x < width; x++) {
                        const uint8_t *pixel = row + x * 4;
                        target[x] = (uint8_t)((29 * pixel[0] + 150 * pixel[1] + 77 * pixel[2] + 128) >> 8);
                    }
                }
                stride = width; gray = _gray;
            } else {
                return [self fail:[NSString stringWithFormat:@"Unsupported AprilTag pixel format: %u.", (unsigned)format]];
            }
            if (!gray || width > INT_MAX || height > INT_MAX || stride > INT_MAX || stride < width)
                return [self fail:@"Invalid AprilTag grayscale dimensions or stride."];
            AFTagDetection *detections = NULL;
            size_t count = 0;
            AFTagCalibration calibration = {0};
            if (intrinsics.count == 4 && [intrinsics[0] isKindOfClass:NSNumber.class] &&
                [intrinsics[1] isKindOfClass:NSNumber.class] && [intrinsics[2] isKindOfClass:NSNumber.class] &&
                [intrinsics[3] isKindOfClass:NSNumber.class]) {
                calibration = (AFTagCalibration){.fx = intrinsics[0].doubleValue, .fy = intrinsics[1].doubleValue,
                    .cx = intrinsics[2].doubleValue, .cy = intrinsics[3].doubleValue, .tagSizeMeters = tagSizeMeters};
            }
            int status = AFTagCoreDetectCalibrated(_core, gray, (int)width, (int)height, (int)stride,
                                                  &calibration, &detections, &count);
            if (status != AFTagCoreSuccess) return [self fail:@"AprilTag detection failed; no results were accepted."];
            NSMutableArray *records = [NSMutableArray arrayWithCapacity:count];
            for (size_t index = 0; index < count; index++) {
                AFTagDetection tag = detections[index];
                NSMutableArray *corners = [NSMutableArray arrayWithCapacity:4];
                for (int corner = 0; corner < 4; corner++)
                    [corners addObject:@[@(tag.corners[corner][0]), @(tag.corners[corner][1])]];
                NSMutableDictionary *record = [@{@"id":@(tag.id), @"family":@"tag36h11", @"hamming":@(tag.hamming),
                    @"decisionMargin":@(tag.decisionMargin), @"center":@[@(tag.center[0]), @(tag.center[1])],
                    @"corners":corners, @"detectionImageWidth":@(width), @"detectionImageHeight":@(height)} mutableCopy];
                if (tag.hasPose) {
                    AFTagPose p = tag.pose;
                    NSMutableArray *rotation = [NSMutableArray arrayWithCapacity:9];
                    for (int i = 0; i < 9; i++) [rotation addObject:@(p.rotationRowMajor[i])];
                    NSMutableDictionary *pose = [@{
                        @"translation":@[@(p.translation[0]), @(p.translation[1]), @(p.translation[2])],
                        @"rotationRowMajor":rotation,
                        @"eulerDegrees":@[@(p.eulerDegrees[0]), @(p.eulerDegrees[1]), @(p.eulerDegrees[2])],
                        @"rangeMeters":@(p.rangeMeters), @"opticalAxisAngleDegrees":@(p.opticalAxisAngleDegrees),
                        @"planeAngleDegrees":@(p.planeAngleDegrees), @"reprojectionRMSEPixels":@(p.reprojectionRMSEPixels),
                        @"poseError":@(p.poseError), @"ambiguous":@((BOOL)p.ambiguous),
                        @"candidateCount":@(p.candidateCount), @"eulerSingular":@((BOOL)p.eulerSingular),
                        @"tagSizeMeters":@(tagSizeMeters), @"coordinateFrame":@"camera-optical-x-right-y-down-z-forward",
                        @"rotationConvention":@"tag-to-camera row-major; R=Rz(yawZ)*Ry(pitchY)*Rx(rollX)",
                        @"poseErrorMetric":@"sum-squared-object-space-ray-distance-m2",
                        @"solver":@"apriltag-orthogonal-iteration-50"
                    } mutableCopy];
                    if (p.hasSecondPose) {
                        pose[@"secondPoseError"] = @(p.secondPoseError);
                        pose[@"secondReprojectionRMSEPixels"] = @(p.secondReprojectionRMSEPixels);
                        pose[@"poseErrorRatio"] = @(p.poseErrorRatio);
                        pose[@"candidateRotationSeparationDegrees"] = @(p.candidateRotationSeparationDegrees);
                        pose[@"candidateTranslationSeparationMeters"] = @(p.candidateTranslationSeparationMeters);
                    }
                    record[@"pose"] = pose;
                }
                [records addObject:record];
            }
            AFTagCoreFreeDetections(detections);
            result = records;
        } @finally {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        }
        return result;
    }
}
@end
