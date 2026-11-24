# Controls within thumb reach

November 23, 2026. Release **0.9.0 (28)**.

The live capture screen has three compact bottom rows:

1. Tags, Measure, Saved and More.
2. Kalman on/off, 1×/2×/4× and Settings.
3. Session name, Record/Stop and Bookmark.

The dock is bottom-anchored and bounded to half the window height. Measurement
controls and preview modes, tag details, saved recordings and app information
open in bounded scrolling panels in that same lower half. Recording remains
pinned while capture tools are open. The camera keeps its full viewport behind
the dock, including through orientation changes; opening a panel does not remount
or resize the camera. Upper camera/status annotations are passive. Scene taps
still select tags, floor planes and measurement endpoints at their image locations.

The interactive native camera Details panel was replaced by a separately mounted
`ARCaptureReadoutView` inside More → Tag details. It uses the same cached selected
result, expires missing/stale data and delegates scrolling to the outer sheet.
Standalone panel behavior is retained for its existing tests. Settings, About and
release notes use bottom sheets; their contents scroll, with reachable actions.

## Checks

- **62 JavaScript tests passed** across six suites. Added coverage includes dock
  containment at five phone/tablet sizes, rotation and recording/name state,
  settings and menu routing, tag details, navigation and Kalman acknowledgement.
- **15 native panel tests passed**, including the separately mounted, passive
  readout and its lifetime. Result: `/tmp/april-readout-panel-tests/Results.xcresult`.
- TypeScript, changed-file ESLint and `git diff --check` pass. Existing no-void
  test warnings remain.
- Signed iPhone Release build and unsigned simulator product build pass, including
  the React Native view manager/bridge. Camera/LiDAR capability is unavailable in
  the simulator; these checks establish UI behavior and layout, not field accuracy.

## iPhone handoff

The signed Release built `2026-11-23T05:01:10Z` embeds version
0.9.0/build28, base commit `44d2692473d2fb5dca2fc115e020c89c0389d4e2` and
`workingTreeDirty: true`. The exact product source footprint was hashed and
verified before packaging. Strict/deep signature, bundled JavaScript, release
notes, provisioning and matching dSYM checks passed before device access.

An in-place install and launch succeeded. Installed-app and process queries
confirmed 0.9.0 (28) running. Complete Documents paths, file sizes and directory
flags matched before and after installation. No recording, screen sharing or
WDA/XCTest/Appium runner was started on the phone. All owned deployment commands
exited; the global guard returned **released** without errors before reporting.

Exact package, symbols, source hashes and private device evidence:
`/tmp/april-thumb-handoff-20261123/`.
Build log: `/tmp/april-thumb-release-build.log`.
Executable SHA-256: `f159c2a1dc7993a018ce9c98e9669de72dfa9d7722389e546d4e8308d75b98c6`.


## Actual native UI frame verification

The bundled simulator app passed **2 complete XCTest UI flows**, portrait and
landscape, with zero failures. Tests inspect native accessibility element frames,
including the React Native Other elements for Tags, Measure, Saved and Kalman.
They traverse session name, Settings, measurement tools, More, About tabs,
release notes, tag details and Saved/return. All inspected interactive frames
remain within the lower half and inside the horizontal screen bounds.

At 402×874 portrait, the default navigation/quick/recording rows start at
696/744/792 points; the halfway boundary is437. At874×402 landscape, they start
at238/286/334 points; the boundary is201. The named primary controls have44-point
frames. Expanded tool content scrolls inside the bounded region while Record
stays pinned. Portrait and landscape full-screen screenshots were visually
reviewed for clipping and overlap. Simulator screenshots show unavailable AR,
which is expected and is not device camera evidence.

Results: `/tmp/april-thumb-ui-tests-v2/Results.xcresult`.
Screenshots: `/tmp/april-thumb-ui-tests-v2/artifacts/`.
The final optimized harness also passed build-for-testing. Its owned app and test
commands exited, and both dedicated Thumb Reach simulators were shut down and
deleted before completion. No physical UI automation was used for this check.
