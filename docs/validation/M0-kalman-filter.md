# Optional Kalman readout smoothing

Settings now has a Kalman filter checkbox and a Smoothing strength dropdown with
3, 5, 10, 20 and 30 equivalent samples. Filtering defaults off, with strength 5.
The selected strength persists while disabled; Apply, Cancel and Reset follow the
existing settings workflow. The checkbox, dropdown and radio options expose their
checked, disabled and expanded states to accessibility.

The filter updates once per fresh, accepted analysis result on the capture queue.
It independently smooths each tag's live floor-height readout and LiDAR/tag camera
ranges. Displayed range differences are recomputed from those filtered ranges.
Cards and the selected height panel identify filtering. Original detection
payloads, status/debug diagnostics, quality gates, spatial vectors, manual
measurements and recording/playback observations remain raw.

This is a scalar random-walk Kalman model with normalized measurement variance
R = 1. For N equivalent samples, nominal gain alpha = 2/(N+1), initial posterior
covariance P = alpha, and process variance Q = alpha²/(1-alpha), scaled by elapsed
time relative to 30 Hz. N controls response strength rather than a fixed history
buffer. First observations pass through immediately. Histories reset on missing
signals/tags, changed source/floor/segment/settings, tracking loss, expiry, invalid
timestamps or gaps above 0.4 seconds. Duplicate IDs in one frame stay raw.

Validation on November 22, 2026:

- Combined native simulator suite: **136 tests passed**, zero failures, including
  12 filter cases, 3 settings cases and filter-to-card/panel presentation checks.
  Results: `/tmp/aprilfools-kalman-regression/Results.xcresult`.
- React Native suite: **53 tests passed** across 6 suites, including 6 filter
  settings cases covering default migration, saving, disabling, reset, cancel and
  reopening. Component tests verify accessibility props; they do not establish
  an end-to-end VoiceOver check of the React Native settings screen.
- TypeScript, changed-file ESLint and the complete native capture integration
  typecheck passed. Existing native deprecation/capture warnings remain.
- The dedicated April Kalman Filter Tests simulator was shut down and deleted.
  No physical device session was started.

Synthetic checks establish lifecycle, numerical and presentation behavior. Real
camera jitter, preferred smoothing strength and motion lag still need evaluation
with physical tags; no physical accuracy improvement is claimed.


## Signed iPhone handoff

At the user's request, **0.8.0 (26)** was built, installed in place and launched
on the iPhone on November 22, 2026. Release notes include optional Kalman
smoothing and the earlier build 25 recording-memory correction.

The Release package was compiled from an isolated checkout of base
`44d2692473d2fb5dca2fc115e020c89c0389d4e2` plus the validated Kalman changes and
exact previously deployed three-file recording-memory fix. The embedded identity
correctly records `workingTreeDirty: true`; build timestamp is
`2026-11-23T04:43:03Z`. Source hashes were checked before packaging.
This isolation excluded incomplete playback work being edited concurrently in
the shared checkout. The initial shared-source attempt failed on missing playback
raster types. The isolated build required the existing working Node installation
and local dependency resolution; no product-code changes were needed to resolve
those build-environment issues.

Strict/deep signature verification, embedded version/build, bundled JavaScript,
release notes, provisioning and matching dSYM UUID checks passed before device
access. The installed-app query confirmed 0.8.0 (26), and a process query confirmed
the app running after launch. The complete Documents listing, directory flags and
file sizes matched before/after installation. No recording was started or deleted.

No screen sharing, Appium, WDA or XCTest runner was started. All owned deployment
commands exited, and the global guard's final status was `released` with no errors
before documentation and cleanup resumed. Installation/launch does not establish
physical camera, filter-tuning or recording/playback acceptance.

Exact app, symbols, source hashes and private deployment evidence are retained
under `/tmp/april-kalman-handoff-20261123/`. Build log:
`/tmp/april-fools-kalman-isolated-build.log`.
Executable SHA-256: `5a91503f128122607459a80557217b70a429345f0285f13ea715a5d8e1503c42`.


## Live toggle: 0.8.1 (27)

The live capture controls now expose a 44-point Kalman on/off checkbox directly
below Tag debug / Measure, including the selected sample count. The separate
Settings dropdown retains smoothing strength. Each tap sends only the enabled
boolean, preserving the native sample setting and exact calibration. The control
waits for native acknowledgement, prevents duplicate requests while pending,
reports errors without a false state change and syncs persisted native status.

Five new interaction cases pass as part of the complete **58-test JavaScript
suite**. TypeScript and changed-file ESLint pass with only existing warnings.
The responsive component tests continue to pass. These component tests validate
accessibility props and state, without claiming a physical VoiceOver/UI check.
The native filter implementation is unchanged from the earlier 136-test suite.

Signed Release **0.8.1 (27)**, built `2026-11-23T04:49:51Z`, passed
signature, bundled JavaScript, version/build, release-note, source-snapshot,
provisioning and matching-symbol checks. Installed-app and process queries
confirmed installation and launch on the iPhone. Documents paths, file sizes and
directory flags matched before and after the in-place update. No screen sharing,
recording or test runner was started. Every owned command exited, and the guard
returned **released** with no errors before this note was written.

Exact package, symbols and private evidence:
`/tmp/april-kalman-live-toggle-handoff-20261123/`.
Build log: `/tmp/april-fools-kalman-live-toggle-build.log`.
