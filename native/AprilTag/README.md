# Shared AprilTag core and iOS adapter

`AFTagCore.h` exposes a portable C API for grayscale8 input with explicit width, height and row stride. A reusable instance owns the upstream detector/family. Default settings: `tag36h11`, two worker threads, `quad_decimate=2`, edge refinement enabled and up to two corrected bits. No tag-size, pose, range or field-placement claims are exposed in this increment.

`AFTagDetector.h/.m` wraps the same core in Foundation/CoreVideo for Swift:

```swift
let detector = AFTagDetector() // reuse on the serial detection worker
if let detections = detector.detectPixelBuffer(pixelBuffer) {
    // NSArray<NSDictionary>: id, family, hamming, decisionMargin,
    // center [x,y], corners [[x,y] x 4], detectionImageWidth/Height
} else {
    // Report detector.lastError; this is not a blank frame.
}
let revision = AFTagDetector.upstreamRevision()
```

The adapter locks the input pixel buffer read-only for the synchronous call, borrows the exact 8-bit Y-plane stride for ARKit's 420f/420v formats, and unlocks before returning. Nonplanar 8-bit grayscale is supported directly. BGRA uses reusable owned grayscale scratch storage and respects its source row stride. Unsupported formats return nil with an error. No ARFrame is retained by this layer.

All coordinates refer to the **original captured image**, top-left pixel origin, x right and y down. Internal quad decimation does not downscale returned coordinates. Corner order is preserved exactly from upstream `apriltag_detection_t.p`; it is tag-relative counter-clockwise, not a screen-sorted top-left ordering. `decisionMargin` is upstream decode quality, not a calibrated placement-confidence score. Use the captured frame's display transform for UI overlays and keep frame association in the caller.

Build the two local implementation files (`AFTagCore.c`, `AFTagDetector.m`) plus every production C path in `third_party/apriltag/sources.txt`. Header search paths: `native/AprilTag` and `third_party/apriltag`. Import `AFTagDetector.h` from the app's bridging header and link Foundation/CoreVideo (system pthread/math are used by the portable dependency). Exclude `tests/` from app compilation.

## Actual detector smoke test

```sh
sh native/AprilTag/tests/run-smoke.sh
```

The host test compiles the actual pinned C detector without React, ARKit, or OpenCV. It renders genuine tag36h11 ID 42 using upstream `apriltag_to_image`, enlarges it into a white grayscale fixture with padded stride, then asserts ID/family/hamming, full-resolution center/corners and blank-image zero detections. It also rejects an invalid stride. This is a synthetic parser/unit smoke test; it does **not** establish physical-camera detection rate, corner accuracy, print quality, or field-calibration accuracy. A real iPhone test is still required.

Dependency revision and complete license notices are in [the vendored README](../../third_party/apriltag/README.md), `LICENSE.md`, and `NOTICE.md`. Retain the notices in distributed app materials.
