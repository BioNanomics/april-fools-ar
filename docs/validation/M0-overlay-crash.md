# AprilTag overlay crash, November 20, 2026

The user reported that the app worked and then crashed. Four device crash reports were retrieved without removing them from the phone. All are from version 0.1.0 build 2 (`9224957`). Their app UUID `A9A2A7C2-DFB7-33DD-8B72-452E9F0419BE` matches the preserved build-2 dSYM.

| Report time, America/Indianapolis | Exception | Common app stack |
| --- | --- | --- |
| 9:29:02 PM | SIGABRT / unrecognized selector | `AprilTagOverlayView.clear → UIView.removeFromSuperview` |
| 9:29:11 PM | EXC_BAD_ACCESS / SIGSEGV | Same |
| 9:29:14 PM | SIGABRT / unrecognized selector | Same |
| 9:29:24 PM | SIGABRT / unrecognized selector | Same |

The first report's actual capture time is 9:28:59 PM; the table uses its report filename time. Raw `.ips` reports, checksums, a ZIP, symbolicated app frames, and matching symbols are preserved locally under `crash-reports/2026-11-20/` (excluded from Git). The latest raw report is `AprilFoolsAR-2026-11-20-212924.ips`.

## Cause and correction

On each detection update, `show` clears the previous tag graphics. The old `clear` removed every sublayer of the overlay view, including backing layers managed by UIKit for the label views, before asking those label views to remove themselves. The four reports fail in that cleanup path; this also explains why the empty-scene smoke check did not expose the issue.

The corrected view tracks its own outline layers and label views explicitly. It removes labels through `removeFromSuperview`, then removes only its own outline layers. It never sweeps UIKit's complete backing-layer list. The existing expiry and empty-result paths use the same corrected cleanup.

The change is in build 3. It preserves recordings and does not change detection or capture formats.

## Verification

- Signed iOS Release build and signature check passed with the cleanup correction.
- Real-UIKit regression checks passed on an iPhone 17 simulator: three tests, zero failures. They cover 250 positive-to-positive-to-empty update cycles, repeated clears, unrelated view/layer preservation, and old/new frame expiry isolation. Reproduce with `ruby native/ARCapture/tests/run-uikit-regression.rb --device-id <booted-simulator-UUID>`; the harness uses the actual production view and a temporary UIKit/XCTest host.
- Running the same tests with `--source-ref 9224957` fails the post-clear hierarchy, unrelated-view/layer preservation, and expiry assertions (`TEST FAILED`, exit 1). The fixed source passes all three tests. Local result bundles are `/tmp/apriltag-overlay-old-uikit/Results.xcresult` and `/tmp/apriltag-overlay-fixed-uikit/Results.xcresult`.
- Fixed implementation `9390894`, version 0.1.0 build 3, was installed in place through Device Hub. It launched successfully on Doug's iPhone 17 Pro and reported normal tracking, live depth and active tag analysis. No physical tag was visible during the post-update observation, so the positive-label regression evidence is the UIKit test above.
- The post-update device still has the same four crash reports, newest at 9:29:24 PM; no new report appeared during the smoke check. Both preexisting session manifests remain present after the update. No app data was uninstalled or deleted.
- Physical tag identification, measurement accuracy, and the full field-review gate are separate from this crash fix.
