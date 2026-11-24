# Persistent version and tag details

November 23, 2026. Release **0.9.1 (29)**.

A passive installed-version/build badge is always present in the upper-right of
the React Native workspace, including Saved and open tool panels. Settings,
About, release notes and the bookmark modal render the same badge above their
backdrops. Native app metadata supplies its value; startup shows an explicit
loading placeholder instead of treating the first bundled release as installed.
It exposes the full version/build to accessibility without adding a top control.

The bottom dock now has a direct Details button. Tapping a current tag outline
or readout card also selects that ID and opens the existing lower-half details
panel, including a repeated tap on the already selected tag after closing it.
Automatic detector selection/status updates do not open or reopen panels.

The native coordinator requires a current decoded ID, normal tracking, a matching
accepted detection, no detector error and a frame age of at most400ms before
emitting ARCaptureTagSelected on main. Pose/depth quality warnings remain
selectable for diagnosis. React ignores malformed IDs and queued selection events
while Saved or a native modal is open, preserving the user's later navigation.
Raw recording data, geometry and filtering calculations are unchanged.

Validation so far:

- All **68 JavaScript tests pass** across six suites, including persistent
  version positioning, direct Details, repeated explicit taps, ID0, malformed
  IDs, queued events and status-only automatic/stale selections.
- TypeScript, changed-file ESLint and git diff whitespace checks pass.
- Signed iPhone Release and unsigned simulator Release builds pass.
- Simulator checks cannot establish actual live AR tag-hit behavior. Manual
  acceptance should tap a tag outline/card, close Details and tap the same tag
  again, then use the bottom Details button and compare the displayed selected ID.


## iPhone handoff

Signed Release **0.9.1 (29)** built `2026-11-23T05:17:30Z`
passed strict/deep signature, source-footprint, bundled JavaScript/release-note,
provisioning and matching-symbol checks. It embeds base commit
`44d2692473d2fb5dca2fc115e020c89c0389d4e2` with `workingTreeDirty: true`.

Installation and launch succeeded in place. The installed-app query confirmed
0.9.1 (29), followed by an app-process query. Complete Documents paths, directory
flags and file sizes matched before and after installation. No recording,
screen sharing or physical WDA/XCTest/Appium runner was started. Owned deployment
commands exited; the global guard's final status is **released**, with no errors.
This verifies deployment and launch, not a physical tag-tap acceptance test.

Exact app, symbols, source hashes and private handoff evidence:
`/tmp/april-version-details-handoff-20261123/`.
Build log: `/tmp/april-version-details-release-build.log`.
Executable SHA-256: `b1fe916978ed8974ef2b27927827492e7af44a6f6e12b6b5dc38e242d6e2d17b`.


## Actual native UI verification

Both actual-product XCTest UI flows passed: **2 tests, zero failures**, portrait
and landscape. They verify the exact0.9.1(29) accessible version value as passive
static text in the upper-right across Capture, Saved, Details, Settings, About
and release notes. The direct Details button remains in the lower half and opens
the native readout from Capture and Saved. Screenshots were visually checked for
version/control overlap. All inspected interactive controls remain lower-half.

Results: `/tmp/april-version-details-ui-tests/Results.xcresult`.
Native screenshots: `/tmp/april-version-details-ui-tests/artifacts/`.
The harness terminated the app, shut down and deleted its owned simulator; final
inventory confirmed no owned Thumb Reach simulators remain. These simulator
checks do not replace a physical live-tag hit/selection acceptance check.
