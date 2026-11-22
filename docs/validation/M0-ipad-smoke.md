# Physical iPad smoke test — 2026-11-22

The signed Release app passed a short native XCTest UI smoke test on an **iPad Pro 11-inch (M5), iPadOS 27.2.1**. This validates launch, live sensor availability and the controls below. It does not close the real-field capture or measurement-accuracy gates.

## Installed package

- Version **0.3.2**, build **14**, bundle `com.doughorner.aprilfoolsar`.
- Source base `8c0d8e6f418e316a10553856b6e3c9b33ce996bc`, with modified sources.
- Embedded build date **2026-11-22T18:00:13Z**; version, build, source marker and date were observed in the installed release-notes view.
- `./scripts/build-ios.sh` passed, including signature and embedded build-identity verification. Installation and launch succeeded without Metro.
- Sources were being edited during preparation. These results apply to the installed package identified above, not to subsequent working-tree changes or a clean commit.

## Results

One native UI test passed, with **zero failures** and no XCTest runtime warnings. The test used the app's actual accessibility labels and identifiers; no coordinate fallback or synthetic camera scene was used.

| Check | Result | Observed evidence |
| --- | --- | --- |
| Launch and release notes | Passed | Installed version/build shown; release notes opened and closed. |
| Live RGB and sensor status | Passed, short observation | Real tabletop/cable imagery; initial limited tracking became `NORMAL`; `DEPTH LIVE` and `READY TO RECORD` appeared. |
| Tag analysis, no-tag scene | Passed, short observation | Approximately 30 Hz, observed frame ages 38–85 ms; `TAG DEBUG · WAITING`. This is not positive tag-detection or sustained performance evidence. |
| Settings | Passed | Settings opened; threshold 15 cm, width 165.1 mm, English units on, pose axes off and floor leveling off were accessible. Cancel closed the sheet without applying changes. |
| Zoom controls | Passed | 2×, 4× and 1× controls were operable through accessibility; 1× was restored. Image/tag alignment was not tested. |
| Landscape accessibility | Passed | Landscape window bounds and accessible/hittable controls were observed. Visual layout remains unverified; see below. |
| Initial floor setup gate | Passed | Measure showed scan instructions, `Looking for the floor…`, and disabled Done. Two-point and height controls remained gated. No floor was confirmed. |
| Saved sessions and return | Passed | Saved sessions opened, showed the empty state, and returned to Live capture. |

## Limits and follow-up

- **Landscape visual check remains pending.** Screenshot attachments contain clipping/orientation artifacts and a large black region, while the accessibility hierarchy reports a landscape window. An unrelated system notification also obscures part of one capture. These observations do not distinguish a screenshot-capture problem from an on-device layout problem. Retest portrait and landscape visually before accepting iPad layout.
- No tag was visible and no usable floor was acquired. Real-tag distance/delta, floor tilt/leveling, automatic height vectors, physical alignment and measurement accuracy remain pending under T0.1e–T0.1j in [the tester checklist](../../TESTER_CHECKLIST.md).
- No recording, bookmark, measurement or export was created. Recording counters remained zero and saved sessions remained empty. Recording/export and the real-field review gate remain open.

## Device release and local evidence

Every physical action used the shared global device guard. Device Hub was blocked by the Mac lock screen, so the prepared native XCTest harness supplied the UI check. No Device Hub screen sharing, keyboard capture, Appium session or WDA runner was started.

The owned host command exited, the exact device-side XCTest runner was verified absent, and the guard returned **`released` with no errors**. The temporary test-runner app was then removed under a separate short cleanup lease; its absence was verified and that lease also returned `released`. The harness restored the original orientation, 1× zoom and Tag debug mode, then terminated the app. April Fools AR remains installed.

Local evidence, intentionally outside the repository:

- `/tmp/april-ipad-test/native-run/Results.xcresult` — native result bundle.
- `/tmp/april-ipad-test/native-run/xcodebuild.log` — test execution log.
- `/tmp/april-ipad-test/evidence/` — exported screenshots and full accessibility observations.
- `/tmp/april-ipad-test/build-latest.log` — signed Release build log.

Device identifiers, lease tokens and raw device output are not included in this report.
