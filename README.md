# April Fools AR

An iPhone-first AprilTag field capture app. Milestone zero detects tags and records real ARKit/LiDAR observations for later analysis; it does not yet solve an AprilTag field calibration.

## On the phone

1. Open **April Fools AR** and allow camera access. Use a LiDAR-capable iPhone for numeric depth recording.
2. Wait for tracking and depth to become available. Point at a `tag36h11` AprilTag to see its ID and corner outline; live detection also runs before recording. The RGB, Depth, and Confidence controls change the preview, not the recorded sensor source.
3. Name the session and tap **Start recording**. Walk past tags and floor/structure surfaces, pausing occasionally and returning toward the starting area.
4. Tap two visible surfaces to inspect estimated 3D distance and gravity-aligned vertical difference. Tap **Clear** to start another pair. Measurements are estimates, not surveyed truth.
5. Use **Bookmark** to add a tag ID, reference measurement, or observation. The source image is retained with the event.
6. Tap **Stop & save**. Open **Saved sessions**, then **Export ZIP** and send the bundle through AirDrop or save it to Files.

Keep recordings short initially and check an export before the first field visit. Files stay on the phone until you explicitly share them. No server, account, BLE meter, or internet connection is needed for capture.

The app stops and saves an active recording when it goes into the background. Keep it in the foreground while recording. ZIP exports support sessions below 4 GiB and temporarily need space for both the session and its ZIP.

## Capture contents

- `rgb.mp4`: camera video, targeting 30 fps.
- `frames.jsonl`: timestamped camera poses, intrinsics, image/display geometry, tracking state, frame identity and sample-file links.
- `frames/`: high-quality camera JPEG samples and bookmarked/measurement frames.
- `depth/`: packed float32 little-endian camera-plane depth in meters, plus uint8 confidence maps. Depth/image samples target 5 Hz.
- `events.jsonl`: AprilTag detections (including analyzed frames with no tags), measurements, notes, interruptions, resets and session events.
- `manifest.json`: capture settings, device/app information, coordinate conventions, totals, errors and file integrity information.

The recorder uses bounded frame retention. Counters and saved diagnostics identify omitted samples; UI update rate is separate from native capture. A heatmap is only a preview—the numeric depth files are the measurement evidence.

See [the capture format](docs/capture-format.md) for coordinate conventions, clocks, buffer layout, and export checks. Run `python3 scripts/inspect-session.py /path/to/session.zip` to inspect a returned recording.

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
- `native/ArchiveModule/`: streaming ZIP export without a server dependency.
- `assets/`: opaque app icon and generation provenance.

The initial detector supports the `tag36h11` family. IDs and image corners do not require knowing tag size. Tag pose estimation, a calibration solver, Android and BLE integration remain later work. REEKON SDK access status is tracked in [reekon-sprint.md](reekon-sprint.md).

The pinned detector's redistribution notices are in [third_party/apriltag/NOTICE.md](third_party/apriltag/NOTICE.md) and are included in the app bundle. The initial family follows [WPILib's FRC AprilTag documentation](https://docs.wpilib.org/en/latest/docs/software/vision-processing/apriltag/apriltag-intro.html).
