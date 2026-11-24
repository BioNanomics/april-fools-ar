# Landscape side controls — 0.11.0 (31)

## Behavior

Portrait keeps capture controls and tools in the lower half. Landscape moves the
capture dock to the safe right edge, below the persistent version badge. The
panel uses less than half the available width and the remaining safe height.
Navigation wraps into three columns; Kalman/Settings and zoom have separate
rows. A scrollable control body supports shorter displays, with recording fixed
below it. More, Details, measurement, Name and Saved reuse the panel; landscape
Saved is one column. Settings uses a taller right panel with scrolling fields
and fixed Cancel/Apply actions. The bookmark editor also aligns right.

Version and About retain their full-screen presentation and bottom navigation.
The native camera remains mounted at its full viewport size while rotating or
opening tool panels, preserving the image projection.

## Automated validation

- All 82 JavaScript tests passed in six suites, including phone/tablet resizes,
  both landscape cutout sides, short displays, state/camera retention, tools,
  saved sessions and Settings drafts. Log: `/tmp/april-landscape-js-tests.log`.
- TypeScript passed. Scoped ESLint has no errors; three static inline-style
  warnings remain in App.tsx. `git diff --check` passed.

## Signed iPhone build

The Release build succeeded and passed strict code-signature, embedded
provisioning, bundle identity, source-snapshot and binary/dSYM UUID checks.
The frozen app, matching dSYM, build identity and source hashes are under
`/tmp/april-landscape-handoff-20261123/`. Build log:
`/tmp/april-landscape-release-build.log`.

Built 0.11.0 (31) at `2026-11-23T06:04:26Z`, from
`44d2692473d2fb5dca2fc115e020c89c0389d4e2` with the working tree marked dirty.

## Physical handoff

The first guarded deployment attempt failed before installation: CoreDevice
could not establish a connection because the peer was unreachable. No install
or launch occurred. The guard completed cleanup and an independent status
query confirmed `released`, with no release errors. The failed attempt was retained privately in
`/tmp/april-landscape-handoff-20261123/attempt-1-unreachable/`.

## Actual native simulator validation

The bundled 0.11.0 (31) app passed all three native XCTest UI flows: portrait,
landscape left, and landscape right (3 tests, 0 failures, 462 seconds). Both
landscape rotations return to portrait with zoom retained. The capture rail is
330 × 294 points on the 874 × 402 point landscape display, at x474/y80, clear of
the safe edge and version badge. Primary actions are hittable and at least
44 points. Settings, More, Details, Name, Measure and Saved stay in the side
area; Record remains pinned. Version/About remain full screen with bottom nav,
including queued Settings/About dismissal-to-Version transitions.

Native screenshots were visually reviewed for both landscape captures,
landscape Settings, and portrait capture. The 26 screenshots and hierarchies
are in `/tmp/april-landscape-ui-tests/artifacts/`; results are in
`/tmp/april-landscape-ui-tests/Results.xcresult`, with the full log beside them.
The harness terminated its app, shut down/deleted its owned simulator, and a
separate simulator inventory confirmed its absence. No physical-device UI
automation was used. These results verify layout/navigation, not AR accuracy.

## Successful physical handoff after reconnection

After the user restored the connection, a new guarded attempt installed and
launched 0.11.0 (31). The installed-app query confirmed version/build, and the
app process was found running. The Documents paths, directory flags and sizes
matched before and after installation, retaining saved recordings. No physical
UI automation, screen sharing or WDA/XCTest runner was started. All owned CLI
commands exited; guard finish and an independent status query both confirmed
`released`, with no release errors. Successful private evidence is under
`/tmp/april-landscape-handoff-20261123/` (summary, install, launch, files and
release JSON). The phone is ready for user testing.
