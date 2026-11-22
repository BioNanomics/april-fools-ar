# Automatic tag height above the floor

Version 0.2.1 (build 10) adds live tag-center height estimates next to tag IDs. Select the floor once per AR coordinate segment; no per-tag target tap is required. Automatic tag heights do not create manual distance/height vectors or consume the manual-measurement limit.

The calculation uses the detected center and the same frame's camera geometry. Usable LiDAR center depth is preferred. A valid tag-pose estimate can supply the center when depth is unavailable, with **Pose** shown as the source. The height is gravity-aligned above the confirmed floor plane, not camera range. Both sources remain estimates.

- [ ] Native height geometry, input/quality rejection, source-frame and floor provenance tests.
- [ ] Actual UIKit ID labels and selected-tag panel accessibility/expiry checks.
- [ ] Signed exact-revision Release build and build-identity verification.
- [ ] Brief Device Hub in-place install/launch and verified device release.
- [ ] Tester checks on real tags/floor and returned recordings in T0.1f.

The existing compact overlay and manual measurements remain available. Missing floor, invalid geometry, stale tracking or a changed coordinate segment must not display a fabricated numeric height. A reset/interruption requires a new floor selection. Real-field accuracy remains a tester check, separate from software geometry tests.

The full native capture integration passed `swiftc -typecheck` against the iOS 27.2 SDK. The existing React Native suites passed 20/20 tests, TypeScript and ESLint; the native height/overlay regression result is recorded below when complete.
