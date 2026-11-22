# Self-contained MP4 export validation

Date: November 22, 2026. Candidate: 0.6.0, build 19.

The isolated MP4 commit excludes pre-existing branding, sponsor, legal and build-script changes. The app, format and native integration checks below were rerun against an exported snapshot of the staged code.

The app's default export is one MP4 containing clean, silent H.264 camera video, three YAML tracks and an original-sidecar TAR track. Live overlays are not burned into the video. The app does not yet include offline overlay playback.

Passed without a physical device:

- `npm test -- --runInBand`: 35 app tests, including finalized-session MP4 sharing and unfinished-session rejection.
- `npx tsc --noEmit`: passed.
- `npm run lint`: no errors; the existing inline-style warning in the capture controls remains.
- `npm --prefix recording-format/npm test`: four format tests, including exact original-file restoration, malformed/unsafe input rejection and a 513 MiB source movie plus a 65 MiB TAR under bounded allocations.
- `python3 native/ArchiveModule/tests/validate-mp4.py`: native Swift export of normal and fast-start synthetic recordings; stock FFmpeg YAML/TAR extraction; unchanged compressed video hashes; exact npm restoration; YAML scalar/Unicode/event-order fidelity; empty logs/files/directories; direct MP4 analysis-inspector parity; source/integrity/size rejection and partial-output cleanup.
- Binary TAR packets are at most 1 MiB; stock FFmpeg extracted multi-packet payloads with `-max_alloc 2097152`.
- Python syntax checks and `git diff --check`: passed. The staged Xcode project parses and includes the MP4 writer in its source build phase.

Before commit isolation, an unsigned Release iOS build also passed in the shared working tree, including native bridge registration and embedded version/build verification. That build included the pre-existing branding and build-script changes excluded from this commit; it was not repeated for the isolated snapshot. Build log: `/tmp/april-fools-ar-mp4-build.log`.

Synthetic fixtures establish file preservation and extraction interoperability. No physical-device install, playback, share-sheet operation or sharing-destination metadata-retention check was performed. Those remain unchecked in [T0.4](../../TESTER_CHECKLIST.md). No physical-device lease or capture session was started.

Format and tools: [recording-format](../../recording-format/README.md).
