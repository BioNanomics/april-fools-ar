# Automatic tag height above the floor

Version 0.2.1 (build 10) adds live tag-center height estimates next to tag IDs. Select the floor once per AR coordinate segment; no per-tag target tap is required. Automatic tag heights do not create manual distance/height vectors or consume the manual-measurement limit.

The calculation uses the detected center and the same frame's camera geometry. Usable LiDAR center depth is preferred. A valid tag-pose estimate can supply the center when depth is unavailable, with **Pose** shown as the source. The height is gravity-aligned above the confirmed floor plane, not camera range. Both sources remain estimates.

- [x] Native height geometry, input/quality rejection, source-frame and floor provenance: 7 new helper cases passed.
- [x] Actual UIKit ID labels and selected-tag panel accessibility/expiry checks passed. Combined native suite: 29/29, zero failures (13 overlay/panel, 9 debug math, 7 height helper). Result: `/tmp/aprilfools-tag-floor-height-20261122/Results.xcresult`. Dedicated simulator was shut down after the run.
- [x] Signed exact-revision Release build and build-identity verification: **0.2.1 (10)**, source `cc1e3a9357128a4338ae43bfc3f781e166275f0b`, built `2026-11-22T15:50:49Z`, clean source tree. Strict/deep signature and embedded metadata comparisons passed.
- [x] Device Hub in-place install/launch on Doug's iPhone 17 Pro (`00008150-001209063CB9401C`). Installed version/build and running PID `9451` verified through `devicectl`; all three original session directories retained. No recording was active before install. Task-owned sharing was stopped; no Appium/WDA/XCTest runners or phone-coordinate input used. All owned commands exited and device controls were released before repository work resumed.
- [ ] Tester checks on real tags/floor and returned recordings in T0.1f.

The existing compact overlay and manual measurements remain available. Missing floor, invalid geometry, stale tracking or a changed coordinate segment must not display a fabricated numeric height. A reset/interruption requires a new floor selection. Real-field accuracy remains a tester check, separate from software geometry tests.

The full native capture integration passed `swiftc -typecheck` against the iOS 27.2 SDK. The existing React Native suites passed 20/20 tests, TypeScript and ESLint; the native height/overlay regression result is recorded above.

Final package: `/tmp/april-fools-final-cc1e3a9/AprilFoolsAR.app`. Build log: `/tmp/april-fools-autoheight-build.log`. Executable SHA-256: `14258788d2f6b5ec5cd44d778b47ad65c4af8b64a8f8c491c693f7e19b9f1554`. Debug symbols are retained locally under ignored `crash-reports/2026-11-22/build10-cc1e3a9/`.

The physical handoff established installation and launch. Actual floor detection, tag-center accuracy and field recordings remain the tester check; no new physical accuracy claim was made.
