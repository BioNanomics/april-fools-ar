# Recording capacity and standalone tag facts

November 24, 2026. Release source: **0.13.0 (36)**.

## Behavior

- **Video + facts** retains the existing camera, JPEG/depth/confidence samples and complete frame/event logs. Source metadata limits increase from 16 to 32 MiB consistently in native export, overlay playback and Node format tools. The 64 MiB generated-YAML and 4 GiB MP4 limits remain.
- **Tag facts only** writes a manifest, optional field definition and standalone `field-walk-summary.yaml`. It creates no video, sample directories or per-frame logs, and bypasses MP4 preparation. Initial/final snapshots are always queued; intermediate checkpoint attempts run at most once per second with only one in flight. Busy intermediate checkpoints are skipped while the live aggregate continues counting.
- The accessible meter shows the most restrictive budget and its units. Source JSONL and generated YAML byte counts are exact; packaging and free-storage budgets are labeled estimates. Automatic saving begins at 95% usage. Export storage budgeting reserves space for the second packaged copy and 250 MB free storage. A single oversized row forces stop even when preceding usage was low and never writes an invalid oversized log.
- Either mode can share its verified summary as a real `.yaml` file independently of an MP4. Facts sessions offer no video playback or evidence links. Bookmarks and saved manual-measurement playback belong to video mode.
- Summary version 2 keeps per-tag counts, latest complete source detection/context and latest usable observation; nominal, registered and segment-local positions retain separate coordinate provenance. Expected tags not observed use `notSeen`, which does not establish physical absence. Discovery works without a field definition; missing coverage requires one. Distinct tags are bounded at 512 and recent registration history at 128, with explicit omission counters.

## Validation

- JavaScript: **147/147 tests**, TypeScript compilation, ESLint with no errors and five existing warnings.
- Native field summary: **37/37 simulator tests**, including full detection/pose/range/angle/source round trips, rejected observations retaining usable evidence, 512 rich tag summaries parsed below the 32 MiB budget, and 100,005 aggregate observations without per-frame retention. `/tmp/april-facts-field-tests-final/FullFactsResults.xcresult`.
- Native recorder: **16/16 simulator tests**, using the real recorder without camera acquisition. Covers durable facts files, absence of media/MP4, duration/counts, invalid/expired finalization, summary integrity, symlinks, independent JSON/YAML budgets, oversized-row stopping, storage reserve, slots reserved for expected tags and bounded checkpoint bursts retaining the final snapshot. `/tmp/april-recording-modes-complete/Results.xcresult`.
- Full Release app UI: mode controls expose correct selected/checked accessibility, accept real taps and meet 44-point hit areas in portrait and landscape. Switching modes starts no recording; mode and Record controls remain separate and visible. `/tmp/april-recording-mode-app-ui-20261124-screen/Results.xcresult`, with full-screen screenshots and accessibility trees in its `artifacts/` directory. The landscape tools above the fixed recording controls remain scrollable.
- Native playback: **51 tests, two expected private-fixture skips, zero failures**, including exact 32 MiB acceptance and rejection one byte above. `/tmp/april-metadata-playback-20261124/Results.xcresult`.
- Node format tools: **6/6 tests**. Native MP4 integration and saved-recording lifecycle pass with metadata above the old limit, exact 32 MiB acceptance, one-byte-over rejection and byte-exact original-file restoration. YAML byte counters match actual exported YAML for nested, Unicode, empty, null and numeric-edge records.
- Memory regression passes on macOS: save 31.2 MiB peak RSS, fresh reopen 11.0 MiB. These are host measurements, not iPhone measurements.
- Unsigned iOS Release build passes. App artifact: `/tmp/april-recording-modes-build/Build/Products/Release-iphoneos/AprilFoolsAR.app`.

Reproduction commands:

```sh
npm test -- --runInBand
npx tsc --noEmit
ruby native/ARCapture/tests/run-recording-tests.rb --work-dir /tmp/april-recording-check
python3 native/ArchiveModule/tests/validate-mp4.py
python3 native/ArchiveModule/tests/validate-saved-recording.py
python3 native/ArchiveModule/tests/validate-recording-memory.py
npm --prefix recording-format/npm test
APRIL_BUILD_DIR=/tmp/april-recording-modes-build ./scripts/build-ios.sh --unsigned
```

All test simulators were task-owned and deleted after their checks. The initial validation above used no physical device. Live camera throughput, physical storage reporting and a real walk reaching automatic-save thresholds remain hardware acceptance checks.

## Signed iPhone and iPad handoff

At the user's request, **0.13.0 (36)** from clean source `f3f453efe67ac26058cf9b4922b90cc0a6007d6a` was signed with the existing local development identity and provisioning profile, then installed in place on the iPhone and iPad. The iPad was initially unavailable and completed after the user requested another Wi-Fi attempt.

Both installed-app queries returned the expected version/build. Documents paths, sizes and directory flags matched before and after each installation, and each exact launched app process was verified running. No recording was created, altered or deleted; no screen capture or WDA/XCTest runner was started. Each physical session completed verified release with no errors. This establishes installation and launch, while the live recording acceptance checks above remain for a real walk.

Private signing, installation, preservation and release evidence is retained under the local temporary `april-recording-modes-handoff-mjplitwh` directory. Device identifiers and lease tokens are excluded from this repository.
