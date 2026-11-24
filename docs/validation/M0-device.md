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

The latest installed update is version 0.1.3 build 8 (`ee60e20`), documented in [M0-status-row.md](M0-status-row.md). Tracking, depth status and zoom controls fit on one line; launch and layout were verified on the phone. Display-only zoom is documented in [M0-view-zoom.md](M0-view-zoom.md). Build identity/release notes are documented in [M0-build-identity.md](M0-build-identity.md), and new recordings retain that package identity. Prior compact-overlay/pose-axis build 5 evidence is in [M0-tag-debug-overlay.md](M0-tag-debug-overlay.md): a real camera screenshot includes tag #5, corners and populated pose/depth values at 29 Hz with limited tracking. Physical axis/zoom checks, sustained normal-tracking validation and export remain open. Earlier build 4 checks are retained in [M0-tag-debug.md](M0-tag-debug.md).

After the short sensor/export check passes, use T0 in [TESTER_CHECKLIST.md](../../TESTER_CHECKLIST.md). Capture an actual field, return the complete bundle, and review it with the user before revising the later roadmap.

## Floor and persistent measurement update — 2026-11-22

Device Hub installed and launched version **0.2.0 (9)** from `d08a7b868aad3057ca06822eabf3a2136a9e7958`. Installed version/build and running PID `9311` were verified, with the original three session directories preserved. No screen sharing or phone test runners were started; device release was verified before further repository work. See [the spatial measurement validation](M0-spatial-measurements.md) for tests, exact build identity and remaining tester checks.

## Automatic tag height update — 2026-11-22

Device Hub installed and launched **0.2.1 (10)** from `cc1e3a9357128a4338ae43bfc3f781e166275f0b`. Installed version/build and running PID `9451` were verified; the original three session directories remain. Task-owned screen sharing was stopped, all deployment commands exited and no phone test runners were started. See [automatic tag-height validation](M0-tag-height.md) for geometry/UI tests, exact build details and pending real-floor checks.

## Height unit preference update — 2026-11-22

Device Hub installed and launched **0.2.2 (11)** from `4398ff7a02526513278c582c9efc99be310fc132`, preserving the three saved sessions. A fresh global device lease covered all physical actions. Accepted full-window evidence and the guard's final `released` status verified cleanup before documentation and push. No test runner, recording or settings changes were made. See [height unit validation](M0-height-units.md).

## Compact multi-tag update — 2026-11-22

Device Hub installed and launched **0.3.0 (12)** from `c24e70a64cedf6ed12eb868fa638411709e2e90c`, preserving three saved sessions. All physical actions used a fresh global device lease; full-window capture proof and final `released` status verified cleanup before repository work resumed. No mirroring, phone-coordinate input, recording or test runners were started. See [multi-tag validation](M0-multi-tag.md).

## Physical iPad smoke test — 2026-11-22

Version **0.3.2 (14)**, built at **18:00:13 UTC** from modified sources based on `8c0d8e6`, passed a native accessibility UI smoke test on an iPad Pro 11-inch (M5), iPadOS 27.2.1. Real RGB imagery, normal tracking and live depth were observed. Release notes, settings, zoom, the initial floor gate and session navigation passed; visual landscape verification, real-tag/floor measurements and recording/export remain pending. The owned XCTest runner exited and was removed, and both test and cleanup leases returned `released`. See [the iPad results and evidence limits](M0-ipad-smoke.md).

## Landscape and tablet update — 2026-11-22

Version **0.4.0 (15)** was installed on the physical iPad and its installed version/build verified after native simulator layout and keyboard checks. iPadOS blocked launch because the iPad was locked; launch and physical alignment checks remain pending. No capture or test runner was started, and the deployment guard returned `released` with no errors. See [landscape and tablet validation](M0-landscape-tablet.md).


## Field and competition-year update — 2026-11-23

Installed and launched **0.10.0 (32)** from clean source commit `45800a7dcb53f2f7980efbaf7008c288140c6bbd` on the iPhone. Captured the explicit FTC/year settings without applying changes. The shared device guard returned **released** after screen-sharing verification, and all owned deployment commands exited. See [field/year validation and the phone screenshot](M0-field-year-tag-sizes.md) for test results, the open physical size check and native accessibility follow-up.
