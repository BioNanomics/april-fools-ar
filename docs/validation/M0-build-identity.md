# Build identity and release notes

Version 0.1.1 (build 6) adds a version/build/short-source identifier in the main header. Tapping it opens release notes and the full installed build identity, including the UTC build date and whether sources were modified. Release history is bundled from `release-notes.json`; its newest entry sets the Xcode version and build number.

An always-run Xcode phase creates `BuildInfo.json` inside the signed app before signing. Command-line builds capture one full Git hash, source-state flag and UTC timestamp for that build. Direct Xcode builds also stamp fresh metadata. The app's screen and recording writer read this same bundle record.

`CaptureRecorder` snapshots the installed identity when a session is created and writes it into `manifest.json.application` and the recording-start event. The build timestamp is separate from the session timestamp. Existing recordings retain their original metadata.

## Checks

- [x] Native metadata parsing, legacy fallback and recording-file snapshot checks: six simulator tests pass, including real recorder initial/final manifests and recording-start events with identical metadata. The source snapshot survives caller changes and keeps build time separate from recording time. No camera frames or physical recordings are simulated as measurement evidence.
- [x] React Native release-notes display and main-header identity checks: all 12 tests pass. Checks include exact installed version/build matching, full source hash and raw UTC visibility, modified-source labeling, Done/native dismissal and missing-info states. TypeScript and ESLint pass.
- [x] Build-phase metadata generation and signed app resource verification. Explicit shell inputs and automatic direct-Xcode metadata generation both pass. The preliminary signed app contains six release entries, and its bundled version/build match the current release and Info.plist. The build script checks full hash, UTC date, source-state flag and version/build after signing.
- [ ] Device Hub in-place installation and on-phone version/release screen check.

This change does not close the real-field recording/review gate in Milestone 0.

Native reproduction: `ruby native/ARCapture/tests/run-build-info-tests.rb --work-dir /tmp/aprilfools-build-info-20261121`; result bundle and full log are retained in that directory.
