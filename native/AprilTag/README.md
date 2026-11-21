# Shared AprilTag core and iOS adapter

`AFTagCore.h` exposes a portable C API for grayscale8 input with explicit width, height and row stride. A reusable instance owns the upstream detector/family. Default settings remain `tag36h11`, two worker threads, `quad_decimate=2`, edge refinement enabled and up to two corrected bits. `AFTagCoreDetect` remains detection-only for compatibility; `AFTagCoreDetectCalibrated` optionally estimates camera-relative tag pose using explicit intrinsics and tag size. No field-relative pose or validated accuracy is claimed.

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

// Calibrated variant. Intrinsics must correspond to this exact captured image.
let records = detector.detectPixelBuffer(
    pixelBuffer, intrinsics: [fx, fy, cx, cy], tagSizeMeters: measuredTagEdge)
// Same detection fields, plus pose dictionary only when a valid pose was solved.
```

The adapter locks the input pixel buffer read-only for the synchronous call, borrows the exact 8-bit Y-plane stride for ARKit's 420f/420v formats, and unlocks before returning. Nonplanar 8-bit grayscale is supported directly. BGRA uses reusable owned grayscale scratch storage and respects its source row stride. Unsupported formats return nil with an error. No ARFrame is retained by this layer.

All coordinates refer to the **original captured image**, top-left pixel origin, x right and y down. Internal quad decimation does not downscale returned coordinates. Corner order is preserved exactly from upstream `apriltag_detection_t.p`; it is tag-relative counter-clockwise, not a screen-sorted top-left ordering. `decisionMargin` is upstream decode quality, not a calibrated placement-confidence score. Use the captured frame's display transform for UI overlays and keep frame association in the caller.

## Calibrated pose contract

The input calibration is `[fx,fy,cx,cy]` in original captured-image pixels, with positive focal lengths, a zero-skew pinhole camera model, and **explicit `tagSizeMeters` measured between detection corners**, excluding the outside paper/white margin. This follows the [upstream pose and coordinate documentation](https://github.com/AprilRobotics/apriltag#pose-estimation). No distortion coefficients are accepted: the caller must provide an image/intrinsics pair appropriate to this pinhole model. The adapter does not rotate, crop, or silently rescale either image or intrinsics.

Missing, nonfinite, zero or negative calibration/size values yield ordinary detections **without a `pose` key**. Broad numerical-safety limits also reject focal lengths outside `[1e-3,1e8]` pixels, principal points with absolute value above `1e8` pixels, and tag sizes outside `[1e-6,1e3]` meters. These bounds prevent unstable numerical inputs; they are not an accuracy or supported-device envelope. A wrong but positive size/calibration can still produce a plausible wrong pose: operator/device verification is required.

The core uses the pinned [two-solution orthogonal-iteration API](../../third_party/apriltag/apriltag_pose.h) with 50 iterations. It selects the least object-space error among finite candidates with a proper orthonormal rotation, positive center Z, and **all four tag corners at positive camera Z**. Nonfinite results, degenerate corner geometry and invalid candidates produce no pose. The corner-only `AFTagCoreEstimatePoseFromCorners` shares this exact solver and is available to portable numerical tests.

| `pose` key | Meaning |
| --- | --- |
| `translation: [x,y,z]` | Tag center in optical-camera meters: x right, y down, z forward. |
| `rotationRowMajor: [9]` | Tag-to-camera rotation; `p_camera = R * p_tag + translation`. Tag x right, y down, z into the printed tag. |
| `eulerDegrees: [rollX,pitchY,yawZ]` | ZYX decomposition with `R = Rz(yawZ) * Ry(pitchY) * Rx(rollX)`. These are tag-relative camera-optical orientation angles, not robot/field yaw. |
| `rangeMeters` | Euclidean center range `sqrt(x²+y²+z²)`, distinct from optical Z for depth comparison. |
| `opticalAxisAngleDegrees` | Unsigned center-ray bearing `atan2(hypot(x,y),z)`, zero on the camera optical axis. |
| `planeAngleDegrees` | Incidence `acos(abs(normal dot normalized center ray))`, in `[0,90]`; zero when viewing the tag plane head-on. This includes off-axis viewing direction. |
| `reprojectionRMSEPixels` | Actual pinhole corner error: reproject the four physical corners through this pose/intrinsics, then `sqrt(sum((du²+dv²))/4)`. It is a 2D per-corner RMS, not a per-coordinate RMS. |
| `poseError` | Upstream **object-space sum of squared distances from transformed corners to their image rays, in m²**. It is neither pixels nor RMS. |
| `candidateCount` | One or two numerically valid positive-depth candidates found by the upstream routine. It is not an exhaustive proof of uniqueness. |
| `ambiguous` | Fixed initial heuristic described below; false does not prove the pose is unique or accurate. |
| `eulerSingular` | `abs(cos(pitch)) < 1e-8`; roll is set to zero and yaw chosen consistently. The rotation matrix remains authoritative at gimbal lock. |
| `tagSizeMeters`, `coordinateFrame`, `rotationConvention`, `poseErrorMetric`, `solver` | Explicit provenance/interpretation strings and applied scale. |

If a second finite positive-depth candidate exists, also return `secondPoseError`, `secondReprojectionRMSEPixels`, `poseErrorRatio`, `candidateRotationSeparationDegrees`, and `candidateTranslationSeparationMeters`. The ratio is selected-best object error divided by the second error, clamped to `[0,1]` (near-equal errors approach one). If both are below `1e-24 * tagSizeMeters²`, the ratio is one rather than 0/0.

`ambiguous` is true only if the ratio is at least **0.8** and the candidates differ by **more than 1 degree** of relative rotation or **more than 1 percent of the tag edge** in translation. The rotation separation uses `acos(clamp((trace(R_best^T R_other)-1)/2,-1,1))`. This avoids labeling converged duplicate frontal solutions ambiguous. These are deterministic engineering heuristics, not a calibrated uncertainty estimate. No invalid/absent second solution is serialized as NaN/Infinity or mistaken for a zero-error alternative.

The tag-plane corner order used for projection is `(-s/2,+s/2,0)`, `(+s/2,+s/2,0)`, `(+s/2,-s/2,0)`, `(-s/2,-s/2,0)`, matching upstream `p[0...3]`. A head-on upright tag has near-identity rotation under these conventions. ARKit's camera axes differ: perform the explicit camera-frame conversion in the AR integration, not inside this portable solver.

Build the two local implementation files (`AFTagCore.c`, `AFTagDetector.m`) plus every production C path in `third_party/apriltag/sources.txt`. Header search paths: `native/AprilTag` and `third_party/apriltag`. Import `AFTagDetector.h` from the app's bridging header and link Foundation/CoreVideo (system pthread/math are used by the portable dependency). Exclude `tests/` from app compilation.

## Actual detector smoke test

```sh
sh native/AprilTag/tests/run-smoke.sh
```

The host test compiles the actual pinned C detector without React, ARKit, or OpenCV. It renders genuine tag36h11 ID 42 using upstream `apriltag_to_image`, enlarges it into a white grayscale fixture with padded stride, then asserts ID/family/hamming, full-resolution center/corners and blank-image zero detections. It also checks a calibrated detected pose, detection-only fallback with invalid size, the legacy no-pose path, and invalid stride rejection.

The second executable projects independently defined frontal, off-axis, oblique and near-frontal tag poses through known intrinsics and solves those corners using the real upstream solver. It checks translation, rotation, Euler conventions, center bearing/incidence, positive-corner depth, candidate metrics, duplicate-frontal non-ambiguity, and explicit scale changes. Noisy corners are independently reprojected to verify the actual pixel RMS; doubling tag size doubles translation/range and quadruples object-space error while leaving pixel reprojection unchanged. Missing/invalid calibration and degenerate/nonfinite corners must fail without fabricated poses.

These are synthetic parser/numerical tests; they do **not** establish physical-camera detection rate, corner accuracy, print quality, or field-calibration accuracy. A low reprojection error also cannot validate the physical tag size. Real iPhone and independently measured geometry tests are still required.

Dependency revision and complete license notices are in [the vendored README](../../third_party/apriltag/README.md), `LICENSE.md`, and `NOTICE.md`. Retain the notices in distributed app materials.
