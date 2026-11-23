# Gravity-relative tag orientation validation

Implemented November 23, 2026 in the working checkout. The feature combines each detected tag's camera-relative rotation with its matching AR frame's gravity-aligned camera pose. It adds live and recorded Tilt/Twist readouts alongside the existing floor-relative tag-center height.

## Behavior

- Tilt is the unsigned departure of the printed plane from vertical: 0° vertical, 90° horizontal.
- Twist is rotation of the printed square from upright within its own plane, positive clockwise when viewed from the printed front. It is unavailable when the gravity projection into the tag plane has magnitude at most `1e-4`.
- The shared C API composes full rotation matrices after the native adapter converts ARKit camera axes to optical axes. It preserves the composed rotation, printed-up direction and into-print normal.
- Orientation requires current normal tracking, matching source-frame geometry and a resolved tag pose passing existing range/incidence/decode/reprojection limits. It does not require a floor or depth. Invalid values remain null rather than becoming zero.
- Height retains the independent confirmed-floor reference and accepted LiDAR/tag-pose source. A numerical integration test verifies a tilted phone recovers both a known tag tilt and its 2.2 m center height using the pose fallback.
- Angle records remain raw when height/distance smoothing is enabled. Recording events retain their frame/segment/timestamp and complete orientation provenance. Playback displays recorded angles and expires them with the source detection; legacy recordings show unavailable angles.

## Verification

- Portable core: CMake Release build and **7/7 CTest checks passed**. The new `gravity_orientation_test` covers independently constructed tilt/twist, horizontal singularity, phone rotation/translation invariance, malformed transforms, ambiguity, quality and age rejection. Build directory: `/tmp/april-fools-gravity-core`.
- Native simulator: **149 tests passed** using `native/ARCapture/tests/run-uikit-regression.rb`. Includes six adapter/integration tests and seven new UIKit orientation tests, valid zero values, missing/malformed inputs, duplicate tag IDs, reused views, expiry and phone/tablet/short-landscape layout. Results: `/tmp/april-gravity-uikit/Results.xcresult`.
- Visually inspected the generated `overlay-gravity-orientation-320x480.png` and `panel-gravity-orientation-390x290.png` in `/tmp/april-gravity-uikit/artifacts`; angles and existing numeric rows fit their cards/panel.
- Playback simulator: **32 passed, 2 optional private-recording checks skipped**, no failures, using `native/ArchiveModule/tests/run-playback-overlay-tests.rb`. The three new orientation tests verify saved values through camera reprojection/backward seeking, lifetime/segment boundaries, zero/horizontal angles and strict value/provenance validation. Results: `/tmp/april-gravity-playback/Results.xcresult`.
- Full unsigned iOS Release app build succeeded with embedded JavaScript and build-identity verification. Artifact: `/tmp/april-gravity-build/Build/Products/Release-iphoneos/AprilFoolsAR.app`; log: `/tmp/april-gravity-build.log`. Package version remains 0.8.2 (28), source base `9baa66e`, working tree marked dirty.
- Read-only review found no actionable defects in frame conventions, quality gates, lifetime or recording preservation. `git diff --check` passed.

## Physical status

No physical-device session, runner, screen capture or install was started during the initial implementation validation above. The task-owned simulator was shut down and removed after testing. The simulator checks establish implementation behavior and native layout, not real-camera numerical accuracy. A subsequent phone handoff is recorded separately below once completed.
