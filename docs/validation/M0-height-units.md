# Height display units

Version 0.2.2 (build 11) presents tag-center and manual floor heights in centimeters, with optional feet/inches in parentheses. **Settings → Show English units** defaults on and is saved on the phone. General distance measurements and raw geometry retain their existing meter units.

For example, 1.42 meters displays as `142.0 cm (4 ft 7.9 in)`, or `142.0 cm` with English units off. Inches round to one decimal before splitting into feet and remaining inches, so rounding across a foot boundary never produces `12.0 in`.

- [x] Formatter and native settings migration/persistence checks passed, including inch carry and preservation of the exact measured tag width.
- [x] JavaScript suites: 25/25 passed, including preference apply/cancel, initial native state, centimeter formatting and optional feet/inches. TypeScript and ESLint passed.
- [x] Combined native suite: 44/44 passed, including tag/panel/vector formatting, accessibility, narrow labels, raw-meter provenance, rounding and settings migration. Result bundle: `/tmp/aprilfools-height-units-20261122/Results.xcresult`. Dedicated simulator was shut down after tests.
- [ ] Signed exact-revision Release build and metadata verification.
- [ ] Guarded physical install/launch and verified global lease release.
- [ ] Tester real-height readability and preference relaunch check in T0.1g.

Changing display units preserves the configured tag width, accepted AR width evidence, and raw numeric measurement values. Display precision is not a claim of physical accuracy.

The complete native capture integration passed `swiftc -typecheck` against the iOS 27.2 SDK.

Before resuming development, the earlier blocked screen-sharing lease was recovered with user authorization. Fresh full-window evidence was accepted by the shared guard, and both `finish` and `status` returned `released` with no errors. No test runner or new capture was started during recovery.
