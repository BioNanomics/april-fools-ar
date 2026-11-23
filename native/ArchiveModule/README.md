# Saved MP4 recordings and native playback

Stopping a recording finalizes the source capture and automatically creates a durable, self-contained MP4 under `Documents/AprilFoolsAR/recordings/<session UUID>.mp4`. Saved sessions offers **Play** and **Share**. Both use that same file; sharing does not make another temporary export on every tap. Play uses native AVKit controls and releases its player on dismissal. The capture view is detached while Saved sessions is open.

In-app playback draws recorded tags, measurements, confirmed floors and tag-height vectors over the clean video. **Recorded overlays** defaults on and can hide the annotations. `RecordingPlaybackTimeline` verifies the retained JSON logs, indexes accepted video frames by their media timestamps and rebuilds geometry at the current playback time. `RecordingPlaybackOverlayView` maps sensor pixels through the video's actual transform and letterboxed video rectangle. Pausing and seeking use playback time rather than live-camera expiry timers. Dismissal removes the time/notification observations along with the player. Missing or invalid metadata leaves a playable clean video with an unavailable explanation. The MP4's pixels and payloads are never rewritten by this viewer.

`SavedRecordingStore` publishes the MP4 atomically, followed by a small receipt containing the original manifest SHA, artifact SHA and file identity. Interrupted/failed packaging preserves the raw session folder and can be retried with Play or Share. Legacy sessions are prepared on first use, with orientation inferred from the first frame. A cross-process file lock serializes publication and permits cleanup of abandoned private staging directories. Listing sessions does not read entire movies or wait on packaging.

Source folders under `Documents/AprilFoolsAR/sessions/` remain immutable recovery/analysis copies. This currently uses extra disk space. They are not discarded automatically. A capture with no completed video remains unfinalized; it cannot be misreported as ready to play.

The bridge keeps `archiveSession(folderPath)` for compatibility but now returns the persistent file. `previewSession(folderPath)` prepares that file if necessary, verifies playability and presents it. Its promise settles when playback is dismissed; concurrent presentation attempts are rejected.

```ts
const recording = await NativeModules.ArchiveModule.archiveSession(folderPath);
// recording: {url, path, bytes, format: "mp4", mimeType: "video/mp4"}
await NativeModules.ArchiveModule.previewSession(folderPath);
```

Call `ARCaptureEngine.exportSession(id)` first to validate the finalized folder. Only direct UUID session directories are accepted. No library package or backend is needed for playback.

The video retains original H.264 image samples. New captures set the track's display transform from the first frame and lock that display orientation for the movie. Screen crop/zoom is not burned into the video. Legacy source orientation can be corrected in the final MP4's active video track while its original movie still restores byte-for-byte. The optional declared transform permits only exact quarter-turn matrices; the reader continues checking every other box and every payload hash.

Metadata numbers are emitted with JSON scalar serialization (valid YAML 1.2), preserving binary64 round trips. The old NSNumber display-string conversion lost precision in real AR camera matrices and has been removed.

Validation:

```sh
npm ci --prefix recording-format/npm
npm --prefix recording-format/npm test
python3 native/ArchiveModule/tests/validate-mp4.py
python3 native/ArchiveModule/tests/validate-saved-recording.py
ruby native/ARCapture/tests/run-build-info-tests.rb --device-id <dedicated-simulator-id>
ruby native/ArchiveModule/tests/run-playback-overlay-tests.rb --device-id <dedicated-simulator-id>
```

The first two native scripts run on macOS without a device. They cover numeric precision, orientation, exact restoration, interrupted publication, concurrent reuse, path checks and retry. Simulator tests cover the player lifecycle, orientation calculation, and empty-capture handling. Physical playback, new recording and sharing remain separate checks.

The playback-overlay suite also checks recorded-time geometry, floor provenance, paused seeking, the visibility toggle, metadata integrity and observer cleanup. See [recorded-overlay validation](../../docs/validation/M0-recorded-overlays.md) for results and optional private-recording checks.

See [container format](../../recording-format/FORMAT.md). `SessionZIPWriter` remains legacy code; the current app shares MP4 files.
