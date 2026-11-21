# Compact camera overlay revision

The previous debug view reserved 270 points below the camera. This revision keeps the AR camera, depth preview and tag outlines at the full preview bounds. The debug readout floats near the bottom, defaults to a translucent 96-point summary, and expands to the detailed readout only when requested. Expansion changes the overlay bounds, not the camera projection or tag coordinate mapping.

The compact view retains tag validity, PnP Z, LiDAR Z, colored difference and live timing. **Details/Collapse** has a 44-point touch target; other points pass through for tag selection. The host's tag-selection recognizer ignores control touches so the button does not also select a tag behind it.

The same update adds an opt-in **Show pose axes** setting. Red X, green Y and blue Z axes project from each solved tag center using the matching source-frame intrinsics and display transform. Missing or invalid pose/calibration cannot produce a gizmo. Existing tag-size settings survive migration, and changing this preference preserves measured-width precision and provenance.

## Validation

- [x] Native panel layout, expand/collapse, current values/colors and touch routing checks: nine tests pass, including long status labels, 44-point button, pass-through hit testing, value colors and 600 reused-view updates. A separate focused test passes for the visible Details/Collapse title after UIKit's deferred button rendering settles.
- [x] Native axis projection/overlay lifetime and settings migration checks: 18 tests pass. They cover camera coordinates and rotation, asymmetric intrinsics, screen transform, invalid calibration/pose, foreshortened Z, individual behind-camera endpoint rejection, 150 reused-axis updates, stale clearing and existing-width migration. All eight React Native tests, TypeScript and ESLint pass.
- [x] Signed iOS Release build 5 and strict/deep signature verification, including the final exact-revision package below.
- [x] In-place Device Hub installation on Doug's iPhone 17 Pro; launch and compact/expanded readouts observed.
- [ ] Additional on-device axes-toggle/persistence, mode-switch and real-tag gizmo checks (T0.1a–b).

![Compact debug overlay with synthetic values](images/tag-debug-compact.png)

This image uses test values to verify the native 390×96-point layout; it is not a physical measurement. The actual camera continues behind the translucent overlay.

Native results: `/tmp/aprilfools-compact-panel-regression-20261121-final/Results.xcresult` and `/tmp/april-fools-axis-regression-20261121/Results.xcresult`. Build log: `/tmp/april-fools-ar-overlay-build.log`.

## Exact-revision package

- Source `b07544c`, version 0.1.0 build 5, bundle `com.doughorner.aprilfoolsar`.
- Package `/tmp/april-fools-final-b07544c/AprilFoolsAR.app`; embedded `BuildCommit` matches the source.
- Final build log `/tmp/april-fools-ar-overlay-build-final.log`; signed Release build and `codesign --verify --deep --strict` pass.
- Executable SHA-256 `321d85ab54762ed9968447e2a5564382592a961578c48ed786ce4ba084ec7f08`.
- Symbol UUID `49C19EBD-07B0-3A0C-A965-B670B84FE653` (arm64); symbols retained under ignored `crash-reports/2026-11-21/build5-b07544c/`.

## Phone observation

Build 5 was installed in place through Device Hub and launched. PID 694 remained running and all three existing session directories were preserved. The compact overlay was observed, followed by Details opening the expanded overlay with a visible Collapse button. The camera-area boundaries stayed unchanged, and the live analysis rate was approximately 30 Hz.

A later device screenshot showed the real camera scene, printed tag #5, its outline/four corners, and populated pose/depth diagnostics. Displayed PnP Z was 0.970 m, LiDAR Z 0.979 m and absolute difference 0.009 m. The UI correctly retained `TRACKING LIMITED` even though the depth-difference cell was green. It showed 29.0 Hz, 83 ms age, 15 ms compute, 0.51 px reprojection RMS, margin 138.9 and zero corrected bits. This is positive live-tag evidence, not independently measured accuracy or normal-tracking acceptance. The physical tag width was not independently checked.

The real-tag screenshot is `/tmp/april-fools-ar-b07544c-expanded.png`; the earlier no-tag expanded screenshot is `/tmp/april-fools-ar-b07544c-expanded-waiting.png`. The camera scene is visible in the real-tag screenshot, resolving the earlier black mirrored-preview uncertainty for this observation.

Screen sharing closed during the next UI action, so automation stopped to leave control with the user. The new axes setting was not exercised on the physical phone in this run; its native persistence and React Native save contract passed the tests above. The preference stayed off. Physical axis alignment, Collapse and mode-switch checks remain on the tester checklist.

Physical known-tag alignment and accuracy checks remain in T0.1a/M0.8; the full Milestone 0 field-data gate remains open.
