# Adaptive controls integration into main

Integrated `codex/kalman-landscape-release` (`f1da6e1`) with main at
`e0f6080` on November 24, 2026. The integration preserves field/year Auto/FTC/FRC
and custom tag sizing, gravity-relative Tilt/Twist readouts, saved-session
deletion, the direct Kalman toggle and sample strength, adaptive capture controls,
full-screen information pages, and direct tag Details navigation.

Conflicts were resolved by combining behavior and tests. The separate passive
Details readout is 290 points high to include main's gravity row and its bottom
rate/calibration row; its surrounding panel remains scrollable. Saved recording
actions wrap inside the narrower landscape panel. Native settings merge/migration
tests cover both the older manual-width schema and field/year plus Kalman state.

The combined release identity is **0.11.1 (33)**, above main's build 32 and the
landscape branch's build 31. Both branches' historical version/build entries are
retained. The generated Xcode project includes both the gravity adapter and
readout filter (63 native sources).

## Validation

- All 106 JavaScript tests passed across 7 suites, including tag-size modes/year,
  saved-session deletion, Kalman state, modal navigation and responsive controls.
  Log: `/tmp/april-merged-js-tests.log`.
- After raising the Details readout height, all 7 responsive tests passed again.
  Log: `/tmp/april-merged-responsive-tests.log`.
- TypeScript passed; scoped lint has no errors, with existing warnings retained.
- An unsigned iPhone Release app build passed, with a nonempty JavaScript bundle
  and verified version/build/source/date metadata. Its bundled release notes
  match the complete merged history. Log:
  `/tmp/april-merged-main-release-build.log`.

The integration validation uses no physical-device session or installation.
The existing phone installation is a previously deployed build; this merge does
not claim a new physical handoff.

The combined native simulator suite passed **170 tests with zero failures**,
including field/year sizing plus Kalman migration/persistence and gravity angles
plus filtered-card/readout composition. All merged Swift/UIKit/core test sources
compiled. Results and screenshots:
`/tmp/april-main-merge-native/Results.xcresult` and
`/tmp/april-main-merge-native/artifacts/`; full log is beside them. The dedicated
simulator was shut down/deleted, and an independent inventory confirmed its
absence. No physical device was involved.
