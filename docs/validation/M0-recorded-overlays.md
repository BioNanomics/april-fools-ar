# Recorded overlays during native playback

Date: November 22, 2026. Candidate: 0.7.1, build 22, modified working tree.

The subsequent device-handoff package uses **0.7.1 (24)** to advance past the previously installed build 23. This changes the package build number, not the playback implementation validated below.

Saved sessions → Play now draws recorded tag outlines/readouts, pose axes, confirmed floors, tag-height vectors and manual measurements over the clean video. Recorded overlays defaults on and has an accessible on/off control. Playback does not rewrite the movie or run a new detector.

The viewer uses accepted video-frame timestamps and camera geometry, recorded event history, the actual video-track orientation and AVKit's displayed video rectangle. Pausing does not expire annotations. Seeking reconstructs the corresponding state. Tracking, segment, floor and settings changes prevent stale geometry from carrying into another context. Missing or invalid metadata leaves playable clean video with an unavailable explanation.

## Verification

- **22 native playback tests passed** on a dedicated iPhone 17 Pro / iOS 26 simulator: source-frame/PTS association, omitted video frames, pose reprojection, stale/empty detections, clear/segment/tracking/settings behavior, backward seeking, floor provenance and immutable measurement floors, metadata integrity checks, four-way video orientation, native player pause/seek/toggle/dismissal and unavailable-data fallback.
- **13 existing build-info/native tests passed** after adding the new playback dependencies to their runner.
- **47 app tests passed**; TypeScript passed. Lint reported no errors and three existing warnings (capture inline style and two test `void` expressions).
- `ruby scripts/bundle-legal.rb --check`, Ruby runner syntax checks and `git diff --check` passed.
- The unsigned Release iOS build passed with version 0.7.1/build 22, including the native bridge and embedded build identity. Command: `APRIL_BUILD_DIR=/tmp/april-fools-ar-playback-overlays-build ./scripts/build-ios.sh --unsigned`.

The previously supplied 5.43-second portrait recording was also reviewed in the simulator. The green outline aligns with the paper tag, and height/range/axis/floor annotations render over the upright video. Full-screen screenshot inspection caught a toggle/AirPlay overlap; the toggle was moved below the native control row, and the final layout passed visibility and control-intersection assertions. Footage was used only in temporary local test resources and was not added to the repository.

Private test artifacts:

- `/tmp/april-fools-recording-overlays-fullscreen/Results.xcresult`
- `/tmp/april-fools-recording-overlays-fullscreen/artifacts/recording-playback-overlays-private.png`
- `/tmp/april-fools-recording-build-info-overlay-regression/Results.xcresult`
- `/tmp/april-fools-ar-playback-overlays-build.log`

The task-owned simulator was shut down, deleted and verified absent. No physical-device session, install or capture was performed. Real-device playback/alignment remains part of [T0.4](../../TESTER_CHECKLIST.md); these checks do not establish sensor accuracy or replay of unrecorded historical UI state.

## Repeat the simulator checks

```sh
ruby native/ArchiveModule/tests/run-playback-overlay-tests.rb --device-id <dedicated-simulator-id>
ruby native/ARCapture/tests/run-build-info-tests.rb --device-id <dedicated-simulator-id>
```

The playback runner optionally accepts `--recording-folder` and `--recording-video` to test a private recording in a generated temporary test bundle. Both options are required together; no recording is copied into the repository.

## Signed iPhone handoff

Installed and launched **0.7.1 (24)** on the user's iPhone 17 Pro from source commit `408a7967e7cd0ac7b458ca2a44488444df6f90e7`. The signed Release build embeds that commit with `workingTreeDirty: false`; its build identity and code signature were verified before installation. The installed-app query confirmed the version and build, and the app's top-level Documents listing was unchanged after the in-place update.

The first attempt could not establish CoreDevice connectivity and made no installation changes. After the user connected and unlocked the phone, the retry completed successfully. Both attempts used the shared global device lease and finished **released** with no cleanup errors. No WDA/XCTest runner or screen-sharing session was started. Private install/release evidence is under `/tmp/april-fools-overlays-handoff-20261122/`; device identifiers and lease tokens are not committed.

This verifies installation and launch. Physical playback interaction and alignment remain for the user's **Saved sessions → Play** check; the overlay behavior and the supplied recording were verified in the simulator as described above.
