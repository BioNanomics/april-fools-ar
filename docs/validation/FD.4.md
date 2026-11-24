# FD.4 — Registered expected field tags

Software validation on November 24, 2026. Expected geometry uses the field package's raw detector-tag transforms in its declared +Z-up field frame, converted through the shared C core to ARKit's +Y-up world. Live rendering reuses `SpatialProjection`, with oriented squares, IDs and normals kept separate from fresh detector outlines.

## Registration policy

The initial inspection tolerances are 10 cm center height, 5° plane tilt, 7° full gravity/printed-up agreement and 15 cm subsequent position disagreement. They are recorded policy settings, not measured accuracy claims. Gravity and height checks use source-frame evidence and a separately confirmed floor; a proposed field alignment never supplies its own validation datum.

| Current state / trigger | Result |
| --- | --- |
| Selected package; no qualified fixed tag | Unaligned, with a next-step explanation. |
| Unknown, moving, ambiguous, stale, limited-tracking or size-conflicting candidate | Retain the seen ID/evidence; do not accept automatic alignment. |
| Failed height, tilt or printed-up check | Remain unaligned; show expected/observed values, tolerances and suggested field/floor/mounting/print-size checks; retain the warning. |
| Height unavailable, angular checks usable | Remain unaligned and explain the missing floor evidence. Only an explicit **Align without height check** request can enable the labeled unverified fallback for that candidate. |
| At least three qualified source frames of the same candidate over at least 0.2 s, with gaps no greater than 0.4 s | Create a provisional single-tag alignment. A second visible tag does not restart the active candidate on each frame. |
| Later fixed tag or return to the anchor disagrees in position, orientation or validation checks | Mark degraded and warn; preserve the registration transform. |
| Clear, recheck, package/sizing/floor change, tracking loss, interruption or coordinate reset | Remove usable alignment and hide expected geometry. Delayed jobs cannot restore a previous generation/segment's registration. |

Passing height/tilt does not prove an anchor's horizontal position or heading. The anchor is marked **assumed-anchor**, and cannot certify its own placement. Comparisons against other tags retain the single-tag registration assumption. Moving FTC cluster members never become permanent fixed anchors; their current observations and timestamps remain separate from expected fixed-field geometry.

The field panel exposes current alignment/checks, expected and observed height/tilt, clear/recheck controls, retained warnings and explicit unavailable values. Current status uses the latest reason while the saved warning list remains history. YAML content is selectable and its actual text is available to accessibility clients.

## Recorded overlays

The recorder pins the full package and exact YAML hash, then records `fieldWalkStarted`, registration changes, invalidations and warnings at their source times. Playback reconstructs registration state from those controls and projects expected fixed tags using the **current movie frame's camera**. Expected tags can persist after a detector outline expires, but never across a stale registration, segment reset or tracking loss. Pause and backward/forward seeking reconstruct their own recorded state. Warning events cannot silently rekey geometry. Legacy recordings without field definitions retain their existing behavior.

The field YAML sidecar is checked against both its inventory hash and the pinned package hash before use. Invalid or missing historical field state leaves expected geometry unavailable instead of inventing placement.

Saved observation links use their original source timestamp relative to the recording origin. The native player seeks to that recorded time and pauses; normal **Play** behavior is unchanged. The field modal must complete its dismissal before the player is presented.

## Reproduction and results

Use a dedicated simulator, following the shared iOS testing skill:

```sh
ruby native/FieldDefinitionTests/run-field-tests.rb \
  --device-id <dedicated-simulator-id> --work-dir /tmp/april-field-native-regression
ruby native/ArchiveModule/tests/run-playback-overlay-tests.rb \
  --device-id <dedicated-simulator-id> --work-dir /tmp/april-field-playback-regression
```

- The final native playback harness completed **35 tests: 34 passed, 1 optional private-recording fixture skipped, 0 failures**. Eight new field cases cover persistent expected placement/current-camera projection, registration changes, backward seeking, invalidation, source segments, tracking loss, settings/floor changes, warning-only events, malformed/legacy data and YAML sidecar hash/symlink integrity. Two additional native preview tests reject invalid observation times and use a real synthetic MP4 to verify a 0.6 s seek that starts/stays paused and releases player ownership after dismissal.
- Final evidence: `/tmp/april-field-observation-playback-final/Results.xcresult`, its `xcodebuild.log` and screenshots under `artifacts/`. The earlier full field-playback run also passed at `/tmp/april-fields-playback-all/Results.xcresult`, with field-only results at `/tmp/april-fields-playback-regression/Results.xcresult`. Both task-owned playback simulators were shut down, deleted and verified absent after testing.
- The native field suite passed **30/30 tests**, including parser/store/import and first-anchor cases in `native/FieldDefinitionTests/FieldDefinitionTests.swift`. Cases include stable/competing candidates, height mismatch, wrong tilt, sloped references, upside-down tags, unavailable floor/manual fallback, unknown/moving tags, delayed generations/segments, inventory boundaries, later translation/yaw disagreement, and overlay clipping/accessibility/lifetime. Evidence: `/tmp/april-field-import-hardening-final/Results.xcresult`. The integration owner records the final full-app UI and clean-source release build results before phone handoff.
- Actual full-app catalog/YAML/import workflows passed **2/2 XCUIApplication tests** at `/tmp/april-field-full-app-ui-3/Results.xcresult`; [FD.3](FD.3.md) records their screenshot/accessibility evidence and the keyboard repair they verified. This is simulator UI evidence, not a physical field walk.
- [FD.2](FD.2.md) records the independent shared transform and anchor fixtures. [FD.3](FD.3.md) records source replay and MP4 byte-exact field transport, plus React Native UI/type checks.

This record claims software behavior verified by host/simulator fixtures. Independent field measurements, real phone motion/zoom/rotation checks and acceptance of the initial thresholds remain FD.6. Robot delivery and later field/visualization expansion remain deferred.
