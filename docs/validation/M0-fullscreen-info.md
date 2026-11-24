# Full-screen application information

November 23, 2026. Release **0.10.0 (30)**.

The upper-right version badge is an accessible44-point button. It and the
Version entry in More open the same full-screen information page. Fixed bottom
navigation switches between Version (installed build/source/timestamp metadata)
and Release notes (the matching current release and full history), with Done.
The badge on that page returns to its Version tab without presenting a second
native modal.

More remains a half-height tool panel. Its single About & sponsors entry opens
one full-screen page containing project/owner information, support and both
sponsor cards. Fixed bottom navigation provides About, Privacy, Licenses &
notices and Done. Existing legal content and sponsor links are preserved.
Settings, tag details and the bookmark form keep their prior half-height layout.

Opaque full-size content uses native overFullScreen presentation. Unlike a
fullScreen UIKit presentation, this keeps the presenting camera view in its
window: ARCaptureView.didMoveToWindow would otherwise detach/pause the session
and begin a new coordinate segment. The reading pages therefore fill the display
while the camera stays mounted behind them.

When the badge is pressed inside About, Settings or Bookmark, the current modal
first closes; Version opens only after native onDismiss. Native Modal components
remain mounted through that callback. Pending/open/closing guards coalesce rapid
taps, prevent overlapping modals and ignore queued tag-selection events while
navigation completes. Session-name/bookmark draft and calibration state are not
saved or rewritten by opening information.

Completed checks:

- All **80 JavaScript tests pass** across six suites, including full-screen page
  structure, footer tabs, both entry paths, combined sponsor content, exact build
  identity/history matching, queued modal handoff, repeated taps and capture state.
- TypeScript, changed-file ESLint and whitespace checks pass.
- Signed iPhone Release and unsigned simulator Release builds pass.


## iPhone handoff

Signed **0.10.0 (30)** built `2026-11-23T05:34:31Z` passed
strict/deep signature, product-source hashes, bundled JavaScript/release notes,
provisioning and matching dSYM checks before device access. Its embedded source
is base `44d2692473d2fb5dca2fc115e020c89c0389d4e2` with `workingTreeDirty: true`.

In-place installation and launch succeeded. Installed-app and process queries
confirmed 0.10.0 (30) running. Complete Documents paths, directory flags and file
sizes matched before/after installation. No recording, screen sharing or
physical WDA/XCTest/Appium runner was started. Owned deployment commands exited;
the global guard returned **released** with no errors before reporting.

Exact app, symbols, source hashes and private evidence:
`/tmp/april-fullscreen-info-handoff-20261123/`.
Build log: `/tmp/april-fullscreen-info-release-build.log`.
Executable SHA-256: `fde632b3ed250d08083843c5f977b5862f157d47710178d4ed2dca132fbcff33`.


## Actual native UI verification

The bundled0.10.0(30) product passed both complete XCTest UI orientation flows:
**2 tests, zero failures**, portrait and landscape. Badge and More both open the
same full-screen Version page. Version/Release notes footer tabs and the local
badge reset work; About combines both sponsor entries and its Privacy/Licenses
footer tabs work. Native About→dismiss→Version and Settings→dismiss→Version
transitions passed in both orientations, without overlapping presentation.

Full-page roots match the application bounds. Portrait402×874 provides615.3pt
Version and665pt About reading viewports, with bottom navigation at y779.
Landscape874×402 provides219.7pt Version and249pt About viewports; all footer
controls are hittable and contained below the screen midpoint. Screenshots were
visually checked. More and tag details retain their lower-half bounds; the upper
version button is the explicit reach exception requested by the user.

The test's original ancestry-based footer query was corrected for the flattened
React Native accessibility tree: exact-label elements are resolved by hittable
frames contained in the footer. This required no product changes.

Results: `/tmp/april-fullscreen-info-ui-tests-v3/Results.xcresult`.
Screenshots/hierarchies: `/tmp/april-fullscreen-info-ui-tests-v3/artifacts/`.
The harness terminated its app, shut down/deleted its own simulator, and final
inventory confirmed no owned Thumb Reach simulators remain. These are simulator
UI checks; no physical UI automation or live-AR accuracy claim is made.
