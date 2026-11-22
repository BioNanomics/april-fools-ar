# Saved MP4 playback and orientation

November 22, 2026. Installed app: **0.7.0 (21)**, source commit `2004e44bf2d5ad8993ba377a4d04c3d7eb507df9`, built at `2026-11-22T21:57:13Z`.

## Findings and fixes

The user supplied a real 5.43-second portrait recording in Downloads. It contains 161 frames of 1920×1440 sensor video and no video-track rotation. All frames report portrait orientation; the correct full-image playback matrix is `[0,1,-1,0,1440,0]`. The recorder now sets its AVAssetWriter input transform from the first frame's sensor-to-display rotation. Raw pixels, camera intrinsics and frame metadata are unchanged.

The real recording also exposed a separate import failure: native `NSNumber.stringValue` shortened some binary64 values, so YAML records did not match the original JSONL exactly. The writer now uses JSON scalar serialization, which is valid YAML 1.2 and preserves numeric round trips. The reader's strict comparison was retained.

Existing recordings can receive a declared playback transform in their active MP4 video track. Readers permit only canonical quarter-turn matrices matching the source dimensions and still verify every other movie box, source-video hash, sidecar hash and original file. The restoration prefix is not altered.

Stop & save now automatically creates a durable MP4 under the sibling `recordings/` directory. Play and Share use that same artifact. Source folders remain recovery copies; failed or expired packaging is retryable and does not invalidate a completed capture. Private partial outputs are cleaned under a cross-process lock. A capture without completed video remains unfinalized.

## Verified evidence

- React Native: **44 tests pass** in the isolated feature checkout and **47 tests pass** with the preserved main-workspace changes; TypeScript passes; lint has no errors (existing inline-style and test `void` warnings).
- Native simulator: **13 tests pass** in the final fresh run, including metadata/empty-capture, native player preparation/dismissal, four-way orientation and an AVAssetWriter orientation round-trip. One earlier test-host launch stalled before tests ran; only this task's test process/simulator was restarted.
- macOS AVAssetWriter: writes three real encoded frames with portrait playback metadata, preserves the landscape sensor raster and its colored quadrants, and verifies the stored matrix and upright playback dimensions through both AVFoundation and ffprobe.
- Native MP4 writer: normal/fast-start movies, exact scalar precision, adjacent/subnormal/extreme doubles, orientation overrides and cancellation cleanup pass.
- Node MP4 tools: **5 tests pass**, including declared/undeclared transform tampering, exact restoration and bounded large-file streaming.
- Saved-recording store: reuse across taps/relaunch, four concurrent processes/instances, interrupted saves, corrupt artifacts, stale-stage cleanup, source preservation and safe-path cases pass.
- Real user recording: corrected playback is clockwise 90° (ffprobe rotation -90); decoded pixels match a clockwise rotation of the original. All **103 source files** restore byte-for-byte, and compressed H.264 samples are unchanged. Shared-core replay reads **120 tag observations** successfully.

Original file SHA256: `794ca9e5887946c67c4094b3718d4273559526023beb5e5774ac91a42ee2d82f` (unchanged).

Corrected copy: `/Users/horner/Downloads/AprilFoolsAR-8EA790BC-upright.mp4`.

Private reproducible proof: `/tmp/april-fools-orientation-recon-20261122/proof/proof.json`; final simulator result `/tmp/afsc-playback-native-2/Fresh.xcresult`; replay `/tmp/afsc-user-clip-replay.jsonl`.

## Physical acceptance

The signed build was installed on Doug's iPhone 17 Pro. The installed-app query reported **0.7.0 (21)**; launch succeeded and the visible app header showed `v0.7.0 (21) · 2004e44`. The app's Documents directory remained present across installation.

Physical preview and return to the session list remain **unverified**. Device Hub exposed its host controls but no app accessibility elements; the coordinate attempt to open Saved sessions returned `noWindowsAvailable`. This does not establish app accessibility or physical playback success. Follow up by retesting the app's Saved sessions / Play / Done accessibility controls and completing **T0.4** on the phone. The simulator player tests passed independently.

Screen sharing was explicitly stopped. The Window menu listed one Device Hub window; its fresh full accessibility tree showed enabled **View Screen**, disabled keyboard capture **off**, and no live-view controls. The global guard verified that evidence and returned **released**, and all task-owned host processes exited. No WDA/XCTest runner was started on the phone. Private handoff evidence is in `/tmp/afsc-playback-handoff` (do not commit its lease token).

Real-field calibration accuracy and full historical AR-overlay playback are not established by this work.
