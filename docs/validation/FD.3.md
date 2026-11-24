# FD.3 — Saved field walks

Software validation on November 24, 2026. These checks exercise synthetic source observations, committed field packages and simulator workflows. Physical field accuracy is covered separately by FD.6.

The phone can select a field by program, complete season and variant; inspect its YAML; import YAML or JSON; and retain validated imports as YAML. Selection is independent of Auto/FTC/FRC/Custom print-size settings. Recording pins the exact field YAML bytes and SHA-256. A recording's package cannot change, and preview observations do not enter its seen-tag inventory.

The shared C reducer counts each source segment/frame/family/ID once. The native inventory retains unknown and rejected-pose IDs, first/last times, accepted/rejected counts, nominal field positions and representative source frame/segment evidence. Unknown or moving tags have an explicit unavailable nominal position. A cluster definition does not imply that its individual members were seen. Matching-frame metric evidence is optional for listing IDs and nominal positions.

After stopping, **Saved sessions → Tags seen** opens the saved walk. YAML is the default view/share format; JSON and CSV are also available. The saved definition and summary travel as ordinary hashed sidecars inside the self-contained MP4.

The list displays the named field coordinate frame; each row retains its representative source frame, segment and timestamp. **Open observation for tag N** dismisses the field modal before opening the recording, paused at that source time. Metadata-only source frames may not be the exact video image at that time; the source identity remains visible. Missing recorded time shows an unavailable link instead of opening an unrelated zero-time frame.

## Source replay

`scripts/replay-field-walk.py` regenerates the inventory from original `aprilTagDetections` events, using the same shipped C inventory reducer as the phone. It verifies the source event/frame inventory and pinned YAML hash. It never reads `field-walk-summary.yaml`, including when that file is absent or corrupt. Original completion order, source segment/frame identities and source timestamps are preserved; metadata-only frames remain observations even when no video sample was appended.

The replay report labels its geometry policy explicitly: observed field positions are projected from original camera/tag poses through the **recorded registration controls**. It does not solve a fresh anchor or certify field accuracy. Its report reproduces seen IDs, family identities, nominal coordinates, counts and first/last times from source evidence. Recorded-state projection diagnostics are distinct from byte-for-byte reproduction of a saved UI summary. Missing source processing-age evidence produces rejected metric counts and an explicit replay note rather than invented freshness.

Build the host library as documented in [FD.2](FD.2.md), then run:

```sh
python3 scripts/replay-field-walk.py /path/to/finalized-session \
  --core-library /tmp/afsc-fields-build/libaf_spatial_core.dylib \
  --output /path/to/new-replayed-walk.yaml
python3 scripts/replay-field-walk.py /path/to/original.mp4 \
  --core-library /tmp/afsc-fields-build/libaf_spatial_core.dylib \
  --output /path/to/new-replayed-walk.json --format json
```

The default is YAML. MP4 input delegates to the existing recording extraction CLI and requires Node 22+; it does not introduce a second extractor. Output must be a new file outside the source session. Older recordings without a pinned field package return an explicit unavailable error instead of inferring a field from IDs or print size.

## Reproduction and results

```sh
export PATH=/Users/horner/.nvm/versions/node/v22.20.0/bin:$PATH
AFSC_LIBRARY=/tmp/afsc-fields-build/libaf_spatial_core.dylib \
  python3 -m unittest scripts/tests/test_field_walk_replay.py -v
npx jest --runInBand --silent
npx tsc --noEmit
```

- **11/11 host replay tests passed.** They cover duplicate source observations, deliberately out-of-order completions, nominal and independently constructed observed positions, source-clock first/last times, unknown IDs, metadata-only frames, stale/disallowed source results, size conflicts, missing timing, reset/segment invalidation, warning snapshots that cannot rekey/revive geometry, explicit legacy unavailability, malformed source records, hash/symlink integrity, YAML/JSON output and protection against changing the source. Log: `/tmp/april-field-walk-replay-final.log`.
- The MP4 case packs and extracts a generated video with the pinned field definition and a deliberately unparsable saved-summary sidecar. Both YAML files, original events, original frames and manifest return **byte-for-byte identical**; regenerated directory, extracted-directory and original-MP4 reports agree. Corrupting or removing the saved summary does not change replay results.
- The full React Native suite passed **90 tests in 7 suites** after the observation-link, YAML accessibility-value and keyboard-dismissal changes. TypeScript and formatting checks passed; focused lint reported no errors and three existing warnings. The tests cover Apply/Cancel, pinning during recording, native import errors, default YAML export, JSON/CSV export, saved read-only summaries, named coordinate frames/source identity, exact recorded-time navigation after modal dismissal, actual YAML accessibility text and retaining the import draft when dismissing its keyboard. Log: `/tmp/april-field-ui-jest-final.log`.
- Native parser/store, inventory, source-boundary and registration cases are exercised by `native/FieldDefinitionTests/run-field-tests.rb`. Latest native suite/build results are recorded with the FD.4 integration evidence; these host checks do not substitute for the full app build.
- **2/2 actual full-app XCUIApplication flows passed**, covering the bundled catalog/selection, YAML accessibility payload and valid JSON import with usable keyboard dismissal. Evidence: `/tmp/april-field-full-app-ui-3/Results.xcresult`, its `xcodebuild.log` and screenshots/accessibility artifacts under `artifacts/`. The task-owned simulator was deleted and verified absent. Exact observation-link arguments and modal-dismissal ordering are covered separately by Jest; native recorded-time seek checks are recorded in FD.4.
- The final native playback suite completed **35 tests: 34 passed, 1 optional fixture skipped, 0 failures**, including valid recorded-time seek/pause and invalid-time rejection. Evidence: `/tmp/april-field-observation-playback-final/Results.xcresult`; see [FD.4](FD.4.md) for details.

Synthetic video checks transport, not camera or LiDAR accuracy. No physical-device action was performed for this host replay validation.
