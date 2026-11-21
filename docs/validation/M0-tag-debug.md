# AprilTag pose/depth debug screen validation

The debug screen adds camera-relative tag pose, frame-matched LiDAR comparison, explicit quality gates, and configurable tag width/thresholds. The implementation remains within the iOS-first native AR pipeline and shared C detector. See [the screen and coordinate definitions](../tag-debug-screen.md).

## Implemented behavior

- Native selected-tag readout with translation, ZYX roll/pitch/yaw, pose Z and range, LiDAR center and 3×3 mean, colored absolute Z difference, plane incidence/center bearing, reprojection RMS, decision margin, corrected bits and validity.
- Reused native labels and tag graphics, four corner dots, tap-to-select, a camera preview above the readout, and stale-result clearing.
- No fixed 8 Hz analysis throttle: one worker accepts available 30 Hz camera frames without building a queue. Actual measured rate, compute time and age are shown. Positive-detection JPEG snapshots are capped at 5 Hz while numeric analysis records remain intact.
- FRC 165.1 mm default width, manual override, and explicitly accepted two-point AR/LiDAR edge estimate. The AR override uses measured world endpoints, not the pose's assumed size. Width source and endpoint evidence are recorded.
- Persisted thresholds with missing/invalid evidence kept neutral. Depth comparison uses optical Z, not Euclidean range; the neighborhood mean never silently replaces a rejected center sample.

## Completed development checks

- Shared C solver tests: known frontal and oblique translations/rotations, in-plane rotation, off-axis geometry, near-frontal ambiguity behavior, tag-size scaling, independently calculated pixel RMS, and invalid/missing calibration or degenerate corners.
- Legacy decoded tag 42, blank image, padded stride and full-resolution corner tests pass.
- TypeScript and ESLint pass. All seven React Native tests pass, including displayed-unit conversion, explicit acceptance of an AR width estimate, full-precision width preservation during threshold edits, and explicit reset to the FRC default.
- Signed iOS Release build 4 passes with the new native components. The final package embeds `BuildCommit=58ebc05` and passes `codesign --verify --deep --strict`.
- Native UIKit/math suite: 12 tests passed. It covers overlay reuse and expiry, optical-Z comparison, warning/rejection boundaries, confidence/missing/NaN inputs, row-stride/normalized depth mapping and neighborhood mean, settings persistence, AR-width validation and matching evidence snapshots.
- Native panel suite: five tests passed for readable metrics, missing/ambiguous states, independent delta colors, threshold boundaries, and 600 updates without recreating labels/layers. The final no-tag telemetry case also passed separately after adding assertions for actual analysis rate, frame age and compute time.

Reproduction commands:

```sh
sh native/AprilTag/tests/run-smoke.sh
ruby native/ARCapture/tests/run-uikit-regression.rb --work-dir /tmp/aprilfools-debug-math-overlay
ruby native/TagDebugPanelTests/run-uikit-panel-regression.rb
npx tsc --noEmit
npm run lint -- --quiet
npm test -- --runInBand
./scripts/build-ios.sh
```

![Native tag debug panel using fixed test values](images/tag-debug-panel.png)

This is a UIKit test fixture, not a physical tag measurement. The image verifies the 390 × 270 point layout and the visible timing footer.

## Preliminary phone check

A working-tree Release build 4 was installed in place through Device Hub on Doug's iPhone 17 Pro (iOS 27.2.1). The app launched, the native no-tag panel rendered, Settings showed the expected defaults, and switching to Measure worked. The analyzed-frame count advanced from 1,280 to 2,155 with displayed compute times around 9–10 ms. No known tag was in view, tracking was limited/initializing, and depth was waiting, so this check does not establish pose/depth accuracy or sustained analysis rate. The AR-width action was subsequently moved immediately below the width field for easier access; the exact-revision installation below checks the final layout.

## Final package

- Source: `58ebc05`, version 0.1.0, build 4, bundle `com.doughorner.aprilfoolsar`.
- Immutable local installation package: `/tmp/april-fools-final-58ebc05/AprilFoolsAR.app`.
- Build log: `/tmp/april-fools-ar-debug-build-final.log`; Release build and strict/deep signature verification pass.
- Executable SHA-256: `6ba09abba3246a442ca46106a97cb50602ede9da14c764505ddaa587dfe9f540`.
- Symbol UUID: `F8760207-BC31-302F-8073-09432BA7B71A` (arm64); retained locally under ignored `crash-reports/2026-11-21/build4-58ebc05/` for any later crash investigation.

## Final phone check

The exact package above was installed in place through Device Hub and launched on Doug's iPhone 17 Pro. Running process: PID 659. Tracking reported `NORMAL`, depth reported live, and the app was ready to record. The final native footer showed 29.7–30.1 analyses/second, 64–80 ms frame age and 3–5 ms compute time during this short no-tag observation. This is an observed idle-scene rate, not a sustained positive-detection or thermal benchmark.

Settings displayed the AR-width action and both instruction lines immediately below the width field. Cancel closed it without applying changes. Tag debug → Measure → Tag debug succeeded with the same process still running. Three existing session directories were preserved; no recording, measurement points or settings changes were created during this check.

No known tag was visible, so neutral/dashed pose and depth-comparison readings were expected; tag accuracy and the AR-width acceptance path still need a real-tag run. The captured/mirrored RGB area remained black even with normal tracking and live depth. Whether the camera preview is visible on the physical phone has been asked of the operator and remains unconfirmed. This run therefore does not establish live-image/outline alignment.

Device screenshots are retained locally at `/tmp/april-fools-ar-58ebc05-debug.png` and `/tmp/april-fools-ar-58ebc05-settings.png`.

## Remaining checks for this build

- [x] Native UIKit/quality-gate regression results and rendered panel inspection.
- [x] Final exact-revision build/signature verification, in-place Device Hub installation, launch and mode-switch checks.
- [ ] Real tag: pose and depth values, selection, threshold colors, manual/AR width override, disappearance/expiry, and sustained actual analysis rate.
- [ ] Captured debug data decoded outside the phone using `scripts/inspect-session.py --require-debug`.

Unit geometry and simulator UI checks do not establish field measurement accuracy. The real-field acquisition/review gate in PLAN.md remains open.
