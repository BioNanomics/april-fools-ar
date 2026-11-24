# Recorded depth and confidence playback

November 23, 2026 UTC. Candidate **0.8.1 (27)**.

The user reported that measurements, depth and confidence were missing when reviewing a recording made with build 25. Inspection confirmed a playback gap: numeric sensor maps were saved, but the player did not load or render them, and the recorder did not save the selected Camera/Depth/Confidence view.

The latest private clip is 8.53 seconds long with 253 accepted video frames, 249 valid tag-4 detections and 43 depth/confidence samples. Tag floor heights and camera distances are present; all video frames have normal tracking. `measurementsAtStart` contains no manual measurements, and no manual point/completion events occur during the clip. The recording therefore cannot establish the history of any manually placed lines outside that capture. Its original preview-view switch sequence is also unavailable.

## Change

Playback now offers **Recorded / Camera / Depth / Confidence**. Explicit Depth/Confidence selection works with compatible older captures. New captures record effective `previewMode` per frame plus initial/change events, allowing Recorded to follow the selected view. Spatial measurement lines remain visible over sensor views; tag cards follow the camera-view behavior.

The timeline merges compatible raw-map descriptors across frame/event records, including omitted video frames and reused paths. Only the latest sample in the displayed frame's segment is eligible, for at most 0.4 seconds. Rendering holds that sampled sensor image; it does not claim a new depth observation or reproject it into a later pose.

Raster IO runs off the main thread, with one request active and one latest desired request. Paths, regular-file status, sizes, dimensions, encodings and SHA-256 are checked before rendering. The image is mapped through the movie's actual video transform and display rectangle. Seek, view changes, disabled overlays and dismissal clear images and reject stale asynchronous completions. Existing capture/export bytes are preserved.

## Validation

- The complete playback suite passed **30 tests**, covering geometry, manual measurement history at recording start, clears/backward seek, recorded-mode history, sample association, expiry, segment boundaries, palette decoding, invalid data, file tampering and path checks, plus native player lifecycle.
- A subsequent targeted native-player run passed **two tests**: the synthetic mode/seek/dismissal regression and an optional test using the actual private clip. It checks the exact loaded Depth/Confidence raster pixels and all four image corners against the video's portrait transform. The first test overlaps the complete suite; there are 31 unique playback cases.
- **13 existing native/build-info tests** passed after adding the new raster dependency to their runner.
- A screenshot-only rerun of the actual-clip test passed after allowing the native segmented-control animation to settle. The resulting Depth/Confidence screenshots show the selected view, aligned maps, tag height, axes and floor geometry. All task-owned simulators were shut down, deleted and verified absent. Simulator work used iPhone 17 Pro / iOS 26; no physical sensor accuracy result is implied.
- Signed iOS Release build, embedded build identity and nested code-signature verification passed for 0.8.1 (27). The build used a frozen source snapshot at `/tmp/april-playback-modes-source-20261123/` and `/tmp/april-playback-modes-build-20261123/`. A temporary Metro watch-folder setting accommodates its shared dependency directory; the main workspace's Metro settings were not changed.
- All five recording-format integration tests and complete private-capture inspection passed; 162 payload files verified with no validation/manifest errors. Ruby syntax checks and `git diff --check` passed.
- Private source footage and sensor data are confined to temporary test resources. Nothing from the user's clip is added to the repository.

Private test evidence:

- `/tmp/april-playback-modes-investigation-20261123/native-tests/Results.xcresult`
- `/tmp/april-playback-modes-investigation-20261123/build-info-tests/Results.xcresult`
- `/tmp/april-playback-modes-investigation-20261123/final-ui-tests/Results.xcresult`
- `/tmp/april-playback-modes-investigation-20261123/final-ui-tests/artifacts/`
- `/tmp/april-playback-modes-investigation-20261123/final-ui-visual-tests/artifacts/`

```sh
ruby native/ArchiveModule/tests/run-playback-overlay-tests.rb --device-id <dedicated-simulator-id>
ruby native/ARCapture/tests/run-build-info-tests.rb --device-id <dedicated-simulator-id>
```

For a private recording, the playback runner accepts `--recording-folder` and `--recording-video`; its temporary test bundle includes referenced depth sidecars. Existing recordings cannot recover unsaved view changes or missing measurement events. Physical recording/playback acceptance remains for the user.

## iPhone handoff

Installed and launched **0.8.1 (27)** in place. The installed-app query confirmed the version/build; the complete Documents entry list, sizes and directory flags matched before/after installation. Existing recordings were not changed. Matching symbols and the frozen native source files are preserved locally under the Git-ignored `crash-reports/2026-11-23/`.

No screen sharing or WDA/XCTest runner was started. All owned deployment commands exited, and the shared device guard returned `released` with no errors. Private handoff evidence is `/tmp/april-playback-views-handoff-20261123/`. The user should choose Depth or Confidence for the existing build-25 clip and make a new recording to test automatic Recorded view changes.
