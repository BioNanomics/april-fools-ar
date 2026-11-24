# Measurement triangle validation

Implemented November 23, 2026. Completed two-point distance measurements now draw their direct distance as the hypotenuse, with dashed cyan horizontal and orange vertical legs. Labels identify D/H/V in meters; V is signed from the first point to the second. The legs use the gravity-aligned world frame, including displacement along both horizontal axes.

## Geometry and behavior

The portable `afsc_distance_triangle` API derives the corner `(end.x, start.y, end.z)` and calls the existing distance calculation for all three lengths. Its thin Swift adapter is shared by live rendering and recorded playback. Existing measurement records, endpoints, floor snapshots and numeric fields are unchanged; the corner is a drawing aid, not another sampled point. Older recordings can derive the same geometry.

Every original edge is clipped independently, so visible legs remain when the hypotenuse is outside the viewport. No screen-space right angle or clipped polygon closure is synthesized. If either leg is at most one micrometer long, redundant helper geometry is suppressed and the D/H/V summary retains its zero values. Completed distance measurements own the additional bounded reusable layers/labels; pending points, tag-width probes and floor heights retain their existing behavior. Tracking loss, expiry and clearing remove the full overlay.

## Verification

- Portable Release build and **7/7 CTest targets passed** in `/tmp/april-measurement-triangle-core`. Coverage includes 3–4–5 geometry, reversed endpoints, signed vertical difference, zero legs/coincident points, nonfinite inputs, overflow, unchanged output on failure, and gravity-aligned world translation/yaw invariance.
- **160 native simulator tests passed**, including live rendering, camera rotation/zoom, independently clipped legs, degenerate cases, pool reuse and cleanup. Narrow-viewport summaries wrap without truncating zero components, and reused normal/height labels reset to one line. Results: `/tmp/april-measurement-triangle-live-final/Results-fixed.xcresult`.
- Playback suite: **36 passed, 2 optional private-recording checks skipped**, no failures. Results: `/tmp/april-measurement-triangle-playback/Results.xcresult`. A final focused rerun passed **15 timeline tests** after restricting triangles to distance records and preserving direct-only rendering for other/missing kinds. Results: `/tmp/april-measurement-triangle-playback-final/Results.xcresult`.
- Visually inspected `/tmp/april-measurement-triangle-live/artifacts/distance-triangle-three-four-five.png`: yellow D = 5 m, cyan H = 3 m, orange V = +4 m, with leg labels outside the triangle.
- Visually inspected `/tmp/april-measurement-triangle-live-final/artifacts/distance-triangle-degenerate-200.png`: a 200-point viewport retains all D/H/V text, including the zero vertical value.
- Three release-note modal checks passed for the updated release history. Read-only review found no remaining actionable geometry, frame, clipping or lifetime defects.
- `git diff --check` passed. No new recording schema or sensor measurement was introduced.

## Physical status

The checks above used simulators and portable math tests. Physical installation and launch are recorded below after the signed phone handoff; those checks do not establish numerical accuracy against independently measured real-world distances.

## Signed iPhone handoff — November 23, 2026

The triangle feature was committed as `bc8b71b8460b63c68ec77dd955b92973ac2ad4fa` on `codex/measurement-triangles`, with the unrelated pending changes left uncommitted. The development-signed Release package **0.9.1 (30)** preserves the previously deployed bottom controls, details sheet, gravity-relative angles and Kalman behavior, together with the current recording/deletion work.

The package passed strict/deep signature verification, provisioning checks for the target phone, embedded version/build/source verification, bundled JavaScript/release-note checks and matching dSYM UUID validation. Source hashes matched before/after building. Embedded source is `bc8b71b`, build timestamp `2026-11-23T05:47:05Z`, and `workingTreeDirty: true` accurately records the preserved pending features in this integrated source tree.

Installed in place and launched successfully. Installed-app metadata confirmed **0.9.1 (30)** and the app process was present after launch. The complete Documents listing, directory flags and file sizes were unchanged across installation. No recording was started or deleted. No screen sharing, Appium, WDA or phone XCTest runner was started; all deployment commands exited and the global device guard returned **released**, with no errors, before this report was written. Both task-owned simulators were removed after testing.

Exact app, symbols, source archive/hashes and private deployment evidence are retained under `/tmp/april-triangle-handoff-20261123/`. Build log: `/tmp/april-triangle-phone-signed-build.log`. Executable SHA-256: `db3d9fead9a23e6708eb12b291ee6359f1178ad47f1a07a6bdfec98b32d30e45`.
