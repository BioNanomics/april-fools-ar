#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Foundation/CoreVideo adapter; the shared C core has no Apple dependency.
/// Reuse on a serial worker queue. A valid blank frame returns an empty array.
@interface AFTagDetector : NSObject
@property (nonatomic, strong, readonly, nullable) NSError *lastError;
+ (NSString *)upstreamRevision NS_SWIFT_NAME(upstreamRevision());
/// Full-resolution captured-image pixels: id/family/hamming/decisionMargin,
/// center [x,y], corners [[x,y] x 4] in upstream corner order.
/// Returns nil and sets lastError for unsupported/invalid buffers or errors.
- (nullable NSArray<NSDictionary<NSString *, id> *> *)detectPixelBuffer:(CVPixelBufferRef)pixelBuffer
    NS_SWIFT_NAME(detectPixelBuffer(_:));
@end

NS_ASSUME_NONNULL_END
