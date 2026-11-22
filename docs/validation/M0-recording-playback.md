# Saved MP4 playback and orientation

November 22, 2026. Candidate app: **0.7.0 (21)**.

## Findings and fixes

The user supplied a real 5.43-second portrait recording in Downloads. It contains 161 frames of 1920×1440 sensor video and no video-track rotation. All frames report portrait orientation; the correct full-image playback matrix is `[0,1,-1,0,1440,0]`. The recorder now sets its AVAssetWriter input transform from the first frame's sensor-to-display rotation. Raw pixels, camera intrinsics and frame metadata are unchanged.

The real recording also exposed a separate import failure: native `NSNumber.stringValue` shortened some binary64 values, so YAML records did not match the original JSONL exactly. The writer now uses JSON scalar serialization, which is valid YAML 1.2 and preserves numeric round trips. The reader's strict comparison was retained.

Existing recordings can receive a declared playback transform in their active MP4 video track. Readers permit only canonical quarter-turn matrices matching the source dimensions and still verify every other movie box, source-video hash, sidecar hash and original file. The restoration prefix is not altered.

Stop & save now automatically creates a durable MP4 under the sibling `recordings/` directory. Play and Share use that same artifact. Source folders remain recovery copies; failed or expired packaging is retryable and does not invalidate a completed capture. Private partial outputs are cleaned under a cross-process lock. A capture without completed video remains unfinalized.

## Verified evidence

- React Native: **44 tests pass**; TypeScript passes; lint has no errors (existing inline-style and test `void` warnings).
- Native simulator: existing metadata/empty-capture, native player preparation/dismissal and four-way orientation checks pass (12 tests in initial run). Additional AVAssetWriter orientation round-trip is exercised in the final simulator run.
- Native MP4 writer: normal/fast-start movies, exact scalar precision, adjacent/subnormal/extreme doubles, orientation overrides and cancellation cleanup pass.
- Node MP4 tools: **5 tests pass**, including declared/undeclared transform tampering, exact restoration and bounded large-file streaming.
- Saved-recording store: reuse across taps/relaunch, four concurrent processes/instances, interrupted saves, corrupt artifacts, stale-stage cleanup, source preservation and safe-path cases pass.
- Real user recording: corrected playback is clockwise 90° (ffprobe rotation -90); decoded pixels match a clockwise rotation of the original. All **103 source files** restore byte-for-byte, and compressed H.264 samples are unchanged. Shared-core replay reads **120 tag observations** successfully.

Original file SHA256: `794ca9e5887946c67c4094b3718d4273559526023beb5e5774ac91a42ee2d82f` (unchanged).

Corrected copy: `/Users/horner/Downloads/AprilFoolsAR-8EA790BC-upright.mp4`.

Private reproducible proof: `/tmp/april-fools-orientation-recon-20261122/proof/proof.json`; simulator evidence under `/tmp/afsc-playback-native-1` and `/tmp/afsc-playback-native-2`; replay `/tmp/afsc-user-clip-replay.jsonl`.

## Physical acceptance

The device handoff separately verifies the installed version, in-app preview of an existing recording, return to the session list, and released Device Hub control. Real-field calibration accuracy and full historical AR-overlay playback are not established by this work.
