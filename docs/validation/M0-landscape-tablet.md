# Landscape and tablet workspace

Version **0.4.0 (15)** adapts the capture workspace to the available window size. iPhone supports portrait and both landscape directions. Landscape phones and roomy iPad windows place the camera beside a tool rail; narrow windows use the compact layout.

## Behavior

- The mode/settings toolbar and recording controls stay fixed while floor and measurement content scrolls in the rail. Short landscape windows temporarily focus the session-name editor above the software keyboard, restoring the normal workspace on Done/blur.
- The same native camera view survives rotation and resizing. The native viewport follows its actual bounds; selected floor, measurements, recording state and display zoom are retained.
- Settings, release notes and bookmark sheets respect safe areas and available height. Tablet settings use columns, release notes use a bounded panel, and saved-session cards use a width-dependent grid.
- The native tag debug panel is capped at 480 points. Expanded metrics scroll in short viewports while Collapse remains reachable; unconstrained readout taps still pass through to the scene.
- Depth and Confidence previews derive their image orientation from the source frame's ARKit display transform. Rotation clears the previous preview before requesting the next frame. Numeric capture buffers and calibration are unchanged.

## Validation

- TypeScript, ESLint and all **33 React tests** passed. Three resize regressions preserve the actual mocked native camera instance, entered name, recording/floor/height state, acknowledged zoom and unsaved settings across phone, tablet and narrow-window dimensions.
- **12 native panel tests** passed, including constrained scrolling, fixed Collapse, viewport growth, tablet width limits and pass-through touches. The final focused short-panel regression also passed.
- **7 native zoom/orientation tests** passed. The new raster test renders the actual UIImageView and checks independently projected color samples for all four quarter-turns and centered aspect-fill crops; invalid transforms are rejected.
- Native simulator accessibility checks exercised iPhone 17 Pro and iPad Pro 11-inch (M5), iOS 26, in portrait and both landscape directions. Capture/console geometry, safe-area bounds, settings, floor setup gating, release notes, session navigation and software keyboard behavior were checked with canonical host screenshots. Simulator camera imagery is unavailable and is not sensor evidence.
- The final full iPhone and iPad layout matrices each passed with zero failures; the separate focused iPhone numeric-keyboard check also passed. Task-created simulators were shut down after validation.
- The short-landscape session-name keyboard failure found during testing was repaired: the focused field and recording action remain visible above the keyboard. Numeric settings keyboard checks verify Cancel and Apply remain reachable.
- Signed physical-device Release build, codesign and embedded build-identity verification passed. The package was built **2026-11-22T18:27:15Z**, from modified sources based on `ae854c6ccb3989c4ca965fa3a7b8af080a7da795`.

## Hardware limits

This layout work does not establish real camera/depth/tag alignment after rotation or measurement accuracy. Complete [T0.1k](../../TESTER_CHECKLIST.md) on live hardware for those checks. The previous physical iPad sensor smoke test remains documented separately in [M0-ipad-smoke.md](M0-ipad-smoke.md).

## Physical iPad handoff

The signed **0.4.0 (15)** package was installed in place on the physical iPad Pro 11-inch (M5), and the installed version/build were independently verified. The running app's Documents directory was empty before the update, so no recording was in progress. No recording, measurement, settings change or test runner was created for this handoff.

iPadOS denied the subsequent launch because the iPad was locked. Launch and physical visual verification therefore remain pending unlock. All deployment commands exited; no screen sharing, keyboard capture, Appium or WDA/XCTest runner was started. The shared guard returned **`released` with no errors** before reporting or waiting for unlock. The app is installed and the iPad is not reserved by this task.

## Local evidence

- `/tmp/april-responsive-test/` — native simulator harness, result bundles, accessibility observations and canonical screenshots.
- `/tmp/april-responsive-test/iphone-final-verified/`, `/tmp/april-responsive-test/ipad-keyboard-fixed/` and `/tmp/april-responsive-test/iphone-numeric-scoped/` — final passing native UI results.
- `/tmp/april-responsive-jest-final.log` — React test results.
- `/tmp/april-native-layout-panel-tests/` and `/tmp/april-native-layout-panel-short-tests/` — native panel checks.
- `/tmp/april-native-layout-depth-tests/` — preview orientation/raster tests.
- `/tmp/april-responsive-device-build.log` — signed build verification.
- `/tmp/april-responsive-handoff/` — private installation, version, launch-error and verified-release evidence.

These local artifacts are not committed. Physical device identifiers and lease tokens are excluded from this report.
