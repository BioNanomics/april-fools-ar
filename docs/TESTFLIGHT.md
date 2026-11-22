# April Fools AR distribution preparation

The app is branded **April Fools AR by The REFINERY**, with **BioNanomics** as its owner. Apple account enrollment and TestFlight upload begin only after the owner's sign-off. This document prepares that work; it does not indicate that an Apple organization account, App Store Connect record, distribution certificate, or TestFlight build already exists.

## Identity and ownership

| Item | Value |
| --- | --- |
| Public app name | April Fools AR by The REFINERY |
| Home-screen name | April Fools AR |
| Owner and copyright attribution | BioNanomics |
| Brand | The REFINERY |
| Website and support contact | https://refineryrobotics.org/ (Contact form) |
| Bundle identifier | `com.bionanomics.aprilfoolsar` |
| URL scheme | `aprilfoolsar` |
| Xcode workspace and scheme | `ios/AprilFoolsAR.xcworkspace`, `AprilFoolsAR` |
| Original source-code license | MIT; see [LICENSE](../LICENSE) |
| Third-party licenses | See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) |
| Privacy policy source | [PRIVACY.md](PRIVACY.md) |

The repository owner will move the repository to The REFINERY's GitHub organization. Preserve history and third-party notices, then update repository links and the local Git remote to the actual transferred URL. No new organization slug is assumed here. Repository transfer and copyright notices do not themselves execute a contributor copyright assignment. Confirm the intended entity owns the original work and any required assignments before distribution.

## Before the owner's sign-off

The earlier branding review build **0.5.1 (18)**, including sponsor acknowledgments, was installed on the iPad. Current source is **0.7.0 (21)** and combines the branding and shared measurement core with durable MP4 saving, upright video playback, and sharing. The earlier **0.5.0 (17)** build passed the full native smoke check; that evidence applies to build 17, not to the current recording and playback changes. See the [branding validation record](validation/M0-refinery-release.md) and [recording/playback validation](validation/M0-recording-playback.md) for build-specific checks and remaining device checks. This is not a TestFlight upload.

- Review the new brand, copyright attribution, MIT license scope, privacy policy, and third-party notices.
- Run JavaScript/TypeScript checks, native simulator regressions, and a Release build with its bundled JavaScript. A simulator verifies UI and logic; it does not verify real ARKit, LiDAR, or camera capture.
- Test the prepared Release build on a LiDAR-capable iPad: camera permission, live camera/depth/confidence, AprilTag detection, floor setup, distance and height measurement, recording finalization and MP4 preparation, saved-session persistence after relaunch, upright native playback, sharing the saved MP4, portrait/landscape layout, and About/privacy access. Check that interrupted MP4 preparation retains the original capture and can be retried with Play or Share.
- Use the shared iOS testing skill at `~/.codex/skills/ios-testing/SKILL.md` and its global physical-device lease for any physical-device action. Build first, keep the device session bounded, and obtain verified release immediately afterward. Store raw device identifiers and lease tokens outside the repository.
- Keep actual test results in a validation note. An unchecked item is pending, not a pass.

## After the owner's sign-off

1. Confirm BioNanomics' exact legal entity name and enroll or select its Apple Developer organization account. Apple verifies legal entity status and normally requires a D-U-N-S number and someone with authority to bind the organization. A trade name alone is insufficient; see [Apple's organization enrollment requirements](https://developer.apple.com/help/account/membership/program-enrollment).
2. Register the explicit bundle ID `com.bionanomics.aprilfoolsar` in that team and create the matching iOS app record in App Store Connect. Pass the selected development team explicitly to the build command without committing account credentials or signing secrets.
3. Publish the approved [privacy policy](PRIVACY.md) at a stable, publicly accessible URL controlled by BioNanomics or The REFINERY. The source file is prepared here; no policy URL is claimed to be live. Enter the actual URL in App Store Connect, along with support and review contact details. Apple requires a privacy-policy URL for iOS apps; see [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).
4. Review the final archive's embedded SDK privacy manifests and actual network behavior. The source audit found local-only recording and user-initiated exports, with no product analytics, ads, accounts, or backend upload. Apple's privacy-label definition concerns data transmitted off-device and retained by the provider or partners. Use that definition and the final build to answer the questionnaire; do not infer answers solely from the empty collected-data array in the app manifest. See [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
5. Select a unique build number, create a signed Release archive, validate it in Xcode Organizer, and upload it to App Store Connect. Inspect processing warnings, privacy requirements, encryption/export-compliance questions, and supported-device information before distributing. This app uses CryptoKit for payload checksums; answer export questions for the actual shipped functionality.
6. Complete TestFlight beta description, What to Test, feedback email, review contact, and review notes. Start with an internal group, then submit the first external build for TestFlight App Review. After approval, share with the intended external group or public link. See [Apple's TestFlight guide](https://developer.apple.com/testflight/) and [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

Local preparation uses `bash scripts/build-ios.sh --unsigned`. After account setup, create the distribution archive with `IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID bash scripts/build-ios.sh --archive`, replacing the placeholder with the selected team's actual ID. The script does not enroll accounts, register devices, or request provisioning updates. An unsigned build verifies compilation and packaging but cannot be installed or uploaded to TestFlight. The default archive path is `/tmp/april-fools-ar-build/AprilFoolsAR.xcarchive`; open the signed archive in Xcode Organizer to validate and distribute it.

## Prepared beta description

April Fools AR by The REFINERY is an experimental robotics field-capture and measurement tool from BioNanomics. Use a LiDAR-capable iPad or iPhone to inspect AprilTags, establish a floor, compare distances and heights, and save local recordings with camera, depth, and measurement data. Stopping a recording prepares a durable MP4. Play its camera video in the app or share the same file, including its embedded recording data, through the system share sheet. Measurements are experimental and have not been certified for surveying, fabrication tolerances, or safety decisions.

## Prepared What to Test

Test camera permission, AprilTag readouts, floor selection, distance and height measurements, device rotation, and short recordings. Stop and save, wait for MP4 preparation, then reopen Saved sessions after an app relaunch. Use Play to verify upright camera video and the native playback controls; close playback and use Share to send that same saved MP4 to a destination you choose. Verify its embedded YAML, images and depth remain extractable after saving or sharing the original file. Check an older saved session, which may need preparation on first use, and retry Play or Share if preparation was interrupted. Compare against a known physical measurement and describe the device, app version/build, lighting, and tag size when reporting a discrepancy. Review the privacy policy before recording or sharing spaces and people. Real LiDAR is required for recording and measurement workflows; the simulator is insufficient.

## Prepared beta-review notes

No sign-in, purchase, or server account is required. Grant camera access. Use a LiDAR-capable iPad or iPhone; place a tag36h11 AprilTag in view for tag-specific checks. Enter the tag's measured physical size in Debug settings. Scan and confirm the floor before measuring height. Start a recording, add a bookmark, then stop and save. The app prepares a durable MP4 while finalizing. Open Saved sessions, select Play for native video playback, close the player, then select Share for the system share sheet. Camera video is silent and has no burned-in overlays; the same file carries readable YAML and the complete original recording data. Original capture files and prepared MP4s remain separately in Documents. If MP4 preparation is interrupted, Play or Share retries from the retained original capture. The app transmits a recording only through the destination chosen in the system share sheet. Live AR measurements are experimental.

## Release record

For each submitted build, record the commit, whether its working tree was dirty, version/build, build date, Xcode/iOS SDK, simulator checks, physical-iPad checks, final artifact identity, privacy/notices review, App Store Connect processing outcome, and external-review status. Keep signing credentials, account identifiers, device identifiers, and lease tokens out of committed notes.
