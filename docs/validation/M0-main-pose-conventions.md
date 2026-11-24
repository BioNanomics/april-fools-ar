# Consolidated main and pose conventions

Validated 2026-11-24 for release 0.12.0 (35).

Main now includes the field-definition catalog and anchored walks, adaptive controls,
Kalman smoothing, live and recorded measurement triangles, and linked offline metric
glossary. Pending recorded Camera / Depth / Confidence views and measurement-history
changes were recovered from the temporary checkouts before their cleanup.

The pose audit adds explicit Raw optical, FTC SDK, and FRC / PhotonVision profiles.
Full rotation matrices drive each conversion. The default FRC / PhotonVision profile
is independent of tag-size selection. FTC projected range, signed bearing and
elevation are distinct from 3D camera distance. Optical depth, viewing incidence,
optical-axis offset, and gravity-relative Lean / Upright have separate labels and
definitions. See [the convention decision](../decisions/004-pose-conventions.md) for
the pinned upstream sources, exact formulas, singularities, and compatibility rules.

Legacy raw pose fields, gravity aliases, threshold persistence keys, and the portable
C/JNI ABI retain their numerical meaning. New recording metadata is additive and
validated against its declared convention. Existing recordings are not rewritten.

## Verification

- TypeScript checking and all 137 Jest tests in nine suites passed.
- The unified simulator UIKit/Swift regression run passed 199 tests. It covers all
  three profiles, accessible settings, glossary links, and the expanded details panel.
- Playback passed 48 tests; two tests requiring optional private recordings were
  skipped. Coverage includes sensor rasters and view modes, measurement history,
  field walks, triangles, lifecycle, and canonical/legacy gravity handling.
- A focused math/settings/readout run passed 65 tests. These overlap the unified
  suite and are not an additional unique test count.
- Portable C/C++/Java verification passed all ten CTest cases, 13 Python replay
  tests, and installed-consumer/header checks. The pose adapter also passed optimized
  and address/undefined-behavior sanitizer runs, including official SDK-generated
  FTC fixtures, compound rotations, singularities, invalid inputs, and wraparound.
- Field-catalog generation was current; all 13 Ruby tests and 129 assertions passed.
- The complete unsigned iOS Release build succeeded for 0.12.0 (35), including
  JavaScript, field definitions, and the offline glossary's 53 anchors and seven
  diagrams. This validation did not install or launch a physical-device build.

The simulator used for this work was shut down after verification. Physical sensor
accuracy is outside this numerical and presentation validation.

## Consolidation recovery

Before consolidation, Git history and the primary checkout's pending changes were
saved outside the repository. All ten secondary checkouts' modified and untracked
files were separately archived and hash-verified. Their branch tips and checkout
HEADs were confirmed to be ancestors of consolidated main before removal. The
private recovery archive is under the owner's Codex archives directory, named
`april-fools-ar-consolidation-20261124T010446`. Private crash reports and dependency
symlink targets were left in place.
