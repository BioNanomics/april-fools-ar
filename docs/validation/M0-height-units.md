# Height display units

Version 0.2.2 (build 11) presents tag-center and manual floor heights in centimeters, with optional feet/inches in parentheses. **Settings → Show English units** defaults on and is saved on the phone. General distance measurements and raw geometry retain their existing meter units.

For example, 1.42 meters displays as `142.0 cm (4 ft 7.9 in)`, or `142.0 cm` with English units off. Inches round to one decimal before splitting into feet and remaining inches, so rounding across a foot boundary never produces `12.0 in`.

- [x] Formatter and native settings migration/persistence checks passed, including inch carry and preservation of the exact measured tag width.
- [x] JavaScript suites: 25/25 passed, including preference apply/cancel, initial native state, centimeter formatting and optional feet/inches. TypeScript and ESLint passed.
- [x] Combined native suite: 44/44 passed, including tag/panel/vector formatting, accessibility, narrow labels, raw-meter provenance, rounding and settings migration. Result bundle: `/tmp/aprilfools-height-units-20261122/Results.xcresult`. Dedicated simulator was shut down after tests.
- [x] Signed exact-revision Release build and metadata verification: **0.2.2 (11)**, source `4398ff7a02526513278c582c9efc99be310fc132`, built `2026-11-22T16:52:44Z`, clean source tree. Strict/deep signature and embedded metadata comparisons passed.
- [x] Device Hub in-place install/launch on Doug's iPhone 17 Pro. Installed version/build and running app were verified; three original session directories were retained. The fresh global lease was checked/renewed for device actions. Full, fresh single-window AX evidence was accepted; `verify-capture`, `finish` and `status` established `released` with no errors. No test runners, phone-coordinate input, recording or settings changes were made.
- [ ] Tester real-height readability and preference relaunch check in T0.1g.

Changing display units preserves the configured tag width, accepted AR width evidence, and raw numeric measurement values. Display precision is not a claim of physical accuracy.

The complete native capture integration passed `swiftc -typecheck` against the iOS 27.2 SDK.

Before resuming development, the earlier blocked screen-sharing lease was recovered with user authorization. Fresh full-window evidence was accepted by the shared guard, and both `finish` and `status` returned `released` with no errors. No test runner or new capture was started during recovery.

Final package: `/tmp/april-fools-final-4398ff7/AprilFoolsAR.app`. Build log: `/tmp/april-fools-height-units-build.log`. Executable SHA-256: `06796f97a458bc08fe7780c7ef0fdb55346ac941ffcb999b4ffd4b701b0da6b7`. Debug symbols are retained locally under ignored `crash-reports/2026-11-22/build11-4398ff7/`.

Physical verification covered installation, launch and release. Real-floor readability and the on-device preference workflow remain the tester check in T0.1g.
