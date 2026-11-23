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

## Signed iPhone handoff — November 23, 2026

Gravity-angle code and release identity were committed as `1d9a490fa2a9401430f579218980b2246d13baf9`. An independent source export of that commit passed **132 native simulator tests**, confirming the committed feature has no dependency on the other pending Kalman or playback changes.

While this package was being prepared, another task installed the thumb-control layout as 0.9.0 (28). The final phone package preserves that layout: bottom controls, quick actions, lower-half sheets and the separate native details readout. Its details view was raised to 290 points for the new gravity row. The isolated release source also preserves current saved-session deletion, recording/playback changes and Kalman settings; the main checkout's other pending edits were left uncommitted. The combined source passed TypeScript, **72 Jest tests** and **151 native simulator tests**, including the passive details panel's lifecycle, freshness and gravity-row containment. The passive 390×290 panel screenshot was visually inspected.

The development-signed Release app **0.9.0 (29)** was installed in place on the iPhone and launched successfully. The installed-app query confirmed its version/build, and a process query confirmed the app running. The complete Documents listing, directory flags and file sizes matched before and after installation. No recording was started or deleted.

The package embeds source commit `1d9a490`, `workingTreeDirty: true` and build timestamp `2026-11-23T05:17:09Z`. The modified-source marker accurately includes the preserved pending features and combined thumb layout. Full source hashes matched before and after the build. Strict/deep signature, provisioning, embedded identity, bundled JavaScript, release notes and matching dSYM UUID checks passed before device access.

No screen sharing, Appium, WDA or XCTest runner was started on the phone. Every owned deployment command exited; the global device guard returned **released**, with no errors, before documentation resumed. This handoff establishes installation and launch, not real-camera numerical accuracy or physical accessibility acceptance.

Exact app, symbols, source archive/hashes and private deployment evidence are retained under `/tmp/april-gravity-handoff-20261123/`. The combined release source remains in the managed `gravity-phone-release` checkout; the app protects it as this chat's primary checkout, so automatic archival was refused. Build log: `/tmp/april-gravity-phone-signed-build-final.log`. Executable SHA-256: `4c6dabd04a8a36b8f7cda388abbb7989410c119a20607861912c910185a4f5a7`.
