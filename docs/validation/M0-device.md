# M0 iPhone deployment and validation

## Build and installation

- Date: 2026-11-20.
- App: **April Fools AR**, version 0.1.0, build 1.
- Implementation revision: `06bd141`; the final Release app embeds this value as `BuildCommit` for exported session manifests.
- Bundle identifier: `com.doughorner.aprilfoolsar`.
- Target: Doug's `DougiPhone17Pro`, iPhone 17 Pro, iOS 27.2.1.
- Toolchain: Xcode 27.2; React Native 0.88.1; React 19.3.0; Node 22.18.0.
- Development signing: Medical Informatics Engineering, Inc. (`X5873NL7XM`).
- Installation: Device Hub → device → Info → Apps → Add → signed Release `.app`.
- Launch: succeeded on the actual phone. React Native controls and native status render; camera permission was granted. Relaunch also succeeded. Release embeds the JavaScript bundle and does not require Metro.
- App icon: generated, opaque 1024×1024 source in `assets/AppIcon.png`; included in the iOS asset catalog.

## Development checks

- `npx tsc --noEmit`: passed.
- `npm run lint -- --quiet`: passed.
- `npm test -- --runInBand`: passed, two control/workflow tests.
- `./scripts/build-ios.sh`: signed physical-device Release build passed.
- `codesign --verify --deep --strict <app>`: passed for the installed build.
- Native ZIP harness: passed archive extraction/byte equality, UTF-8/hidden files, empty directories, symlink/path containment and unsupported ZIP64 boundary checks. See `native/ArchiveModule/README.md`.

The build configuration declares the generated JavaScript bundle as a script output, ensuring that an incremental JavaScript update precedes code signing. The build script verifies the final signature and fails if it is invalid.

## Live sensor check: pending

The initial phone launch showed a black RGB preview, `LIMITED` tracking and `DEPTH WAITING`. An external active call/video overlay was visible at the same time; it has not been ended or modified. That observation does not establish the cause of the missing camera/depth. A relaunch after granting camera access did not resolve it. The user has been asked to free the camera and point the rear cameras at a room/floor for the live check.

Final device check: the exact `06bd141` Release build was installed through Device Hub and launched successfully; `devicectl` confirmed its running process. The final screen showed `LIMITED`, reason `initializing`, and `DEPTH WAITING`. It remains at the capture screen, with no recording started. The installed code includes RGB/depth/confidence previews, measurement controls, notes, native recording, and ZIP export, but these sensor-dependent paths have not yet passed live verification.

No real session has yet been exported or validated. A successful build and app launch do **not** establish that measurement or recording works. M0.8, field capture M0.9, review M0.10, and the overall M0 gate remain open.

When the camera is available, complete this short check:

- [ ] Confirm visible RGB, normal tracking, and live depth; switch Depth/Confidence previews.
- [ ] Record a short session, select two valid points, and add a bookmark.
- [ ] Stop/save and export the session ZIP using the app.
- [ ] Copy the ZIP to the Mac and run `scripts/inspect-session.py`; decode its RGB video and inspect numeric depth/confidence, geometry and event associations.
- [ ] Record session location, manifest/ZIP checksums, rates, drops, and any errors here.
- [x] Confirm the final installed build launches again without Metro (exact `06bd141` build).

## Next field activity

The detector-enabled build 2 is documented in [M0-apriltags.md](M0-apriltags.md). It supersedes the initial capture-only implementation while retaining the same open physical capture/export and field-review gates.

The latest installed update is debug-screen build 4 (`58ebc05`), documented in [M0-tag-debug.md](M0-tag-debug.md). Its final short device check reported normal tracking, live depth and approximately 30 analyses/second with no visible tag. Launch, settings layout and mode switching passed; positive tag/depth comparison, physical RGB-preview confirmation and export validation remain open.

After the short sensor/export check passes, use T0 in [TESTER_CHECKLIST.md](../../TESTER_CHECKLIST.md). Capture an actual field, return the complete bundle, and review it with the user before revising the later roadmap.
