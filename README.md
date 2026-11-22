# April Fools AR

An AprilTag field capture app for iPhone and iPad. Milestone zero detects tags and records real ARKit/LiDAR observations for later analysis; it does not yet solve an AprilTag field calibration.

In landscape, the camera sits beside a tool rail with recording controls kept in reach. Roomy iPad windows use this layout in either orientation; smaller windows return to the compact layout. Floor setup and measurement tools scroll in the rail, settings and release notes use bounded tablet panels, and saved recordings form a grid when space allows. Rotation keeps the current camera session, selected floor, measurements and view zoom.

## On iPhone and iPad

The header shows the installed version, build number and short commit hash. Tap it for **Version and release notes**, including the full source hash, UTC build date and whether the build contains modified sources. New session manifests and recording-start events retain the same identity.

**Tag debug** uses a compact translucent overlay over the full camera preview. It shows validity and pose/LiDAR depth agreement; tap **Details** for translation, orientation, range, angles and decode quality, or **Collapse** to reclaim the view. Tap a tag to select it. Use **Settings** for the physical tag width and quality thresholds; width defaults to FRC 165.1 mm. You can enter a width or use **Measure tag width with AR**, then review and accept the two-point edge estimate. See [debug definitions and conventions](docs/tag-debug-screen.md).

Enable **Show pose axes** in Settings to add red X, green Y and blue Z axes to each solved tag pose.

Use **1× / 2× / 4×** or pinch the live preview for view zoom. It magnifies the image and keeps tag graphics and measurement taps aligned. The recorded RGB/depth and pose calculation keep their original camera calibration; this is display magnification, not a lens change or added optical detail.

Tracking, depth status and zoom controls share one compact line at the top of the preview.

1. Open **April Fools AR** and allow camera access. Use a LiDAR-capable iPhone or iPad for numeric depth recording.
2. Wait for tracking and depth to become available. Point at a `tag36h11` AprilTag to see its ID and corner outline; live detection also runs before recording. The RGB, Depth, and Confidence controls change the preview, not the recorded sensor source.
3. Name the session and tap **Start recording**. Walk past tags and floor/structure surfaces, pausing occasionally and returning toward the starting area.
4. In **Measure** mode, tap two visible surfaces to inspect estimated 3D distance and gravity-aligned vertical difference. Tap **Clear** to start another pair. Measurements are estimates, not surveyed truth.
5. Use **Bookmark** to add a tag ID, reference measurement, or observation. The source image is retained with the event.
6. Tap **Stop & save**. Open **Saved sessions**, then **Export MP4** and send the recording through AirDrop or save it to Files.

Keep recordings short initially and check an export before the first field visit. Files stay on the phone until you explicitly share them. No server, account, BLE meter, or internet connection is needed for capture.

The app stops and saves an active recording when it goes into the background. Keep it in the foreground while recording. MP4 exports must remain below 4 GiB and temporarily need space for both the original session and its exported MP4.

## Capture contents

- `rgb.mp4`: clean, silent H.264 camera video, targeting 30 fps. Live overlays and preview zoom are not burned into the video.
- `frames.jsonl`: timestamped camera poses, intrinsics, image/display geometry, tracking state, frame identity and sample-file links.
- `frames/`: high-quality camera JPEG samples and detection/bookmark/measurement frames.
- `depth/`: packed float32 little-endian camera-plane depth in meters, plus uint8 confidence maps. Depth/image samples target 5 Hz.
- `events.jsonl`: AprilTag detections (including analyzed frames with no tags), measurements, notes, interruptions, resets and session events.
- `manifest.json`: capture settings, device/app information, coordinate conventions, totals, errors and file integrity information.

The recorder uses bounded frame retention. Counters and saved diagnostics identify omitted samples; UI update rate is separate from native capture. A heatmap is only a preview—the numeric depth files are the measurement evidence.

The exported MP4 carries that camera video plus readable session/frame/event YAML and a TAR data track containing the original images, numeric buffers and JSON/JSONL files. A normal player shows the clean video. Tag outlines, measurements and other live graphics stay separate from the pixels so later analysis can use the original imagery; their recorded geometry supports a future overlay viewer. The app does not yet include an offline overlay player.

See [the recording format and extraction commands](recording-format/README.md) and [the capture data conventions](docs/capture-format.md). Install the local extractor with `npm ci --prefix recording-format/npm`, then run `python3 scripts/inspect-session.py /path/to/recording.mp4` to inspect a returned recording. Legacy ZIPs and copied session directories remain readable by the inspector.

## Build

Requirements: Node 22.13 or newer compatible with React Native 0.88, Xcode, CocoaPods, and an Apple development team with the target phone registered.

```sh
npm ci
cd ios
pod install
cd ..
./scripts/build-ios.sh
```

`scripts/configure-ios.rb` includes the native modules and configures the development team and bundle ID. The Release build embeds JavaScript and can launch without Metro. Default output: `/tmp/april-fools-ar-build/Build/Products/Release-iphoneos/AprilFoolsAR.app`.

Add each release to the front of `release-notes.json`, with its version, increasing build number and user-facing changes. The configuration script uses that first entry for Xcode's version/build. Both command-line and direct Xcode builds run `scripts/stamp-build-info.sh` before signing to embed fresh source and UTC build metadata in `BuildInfo.json`. A modified working tree is explicitly marked; release builds should come from the committed source.

Install that `.app` using Device Hub → the target iPhone → Apps → Add. The current bundle ID is `com.doughorner.aprilfoolsar`.

```sh
npx tsc --noEmit
npm run lint
npm test -- --runInBand
```

These development checks do not establish sensor accuracy. [PLAN.md](PLAN.md) keeps the milestone open until a real-field capture is returned and reviewed. [TESTER_CHECKLIST.md](TESTER_CHECKLIST.md) describes that capture.

## Implementation

- React Native/TypeScript: capture controls, session list, bookmarks, export workflow.
- `native/ARCapture/`: Swift ARKit/RealityKit view, measurement probe, native recorder and React Native bridge.
- `native/AprilTag/` and `third_party/apriltag/`: portable AprilTag 3 core, pinned upstream sources and iOS pixel-buffer adapter.
- `native/ArchiveModule/`: streaming self-contained MP4 export without a server dependency.
- `recording-format/`: YAML/MP4 format documentation and npm extraction tools.
- `assets/`: opaque app icon and generation provenance.

The initial detector supports the `tag36h11` family. IDs and image corners do not require knowing tag size; metric pose does. A field calibration solver, Android and BLE integration remain later work. REEKON SDK access status is tracked in [reekon-sprint.md](reekon-sprint.md).

The pinned detector's redistribution notices are in [third_party/apriltag/NOTICE.md](third_party/apriltag/NOTICE.md) and are included in the app bundle. The initial family follows [WPILib's FRC AprilTag documentation](https://docs.wpilib.org/en/latest/docs/software/vision-processing/apriltag/apriltag-intro.html).
