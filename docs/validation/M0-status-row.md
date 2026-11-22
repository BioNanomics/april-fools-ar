# Single-line camera status and zoom

Version 0.1.3 (build 8) combines tracking status, depth status, the current view magnification and the 1×/2×/4× buttons into one 44-point-high translucent row. The separate second zoom row is removed. Status text stays on one line and can shrink slightly for longer status messages; zoom buttons retain their existing touch targets and behavior.

The change affects the React Native layout only. Camera geometry, raw data, pose/depth calculations and native pinch handling retain the behavior verified in [M0-view-zoom.md](M0-view-zoom.md).

- [x] TypeScript, lint and all 15 existing app tests pass.
- [x] Signed exact-revision build and identity checks.
- [x] Device Hub installation and visual check that status and zoom fit on one line. `LIMITED`, `DEPTH WAITING`, `View 1.0×` and all three presets fit without clipping or wrapping on Doug's iPhone 17 Pro. The app remains running as PID 6527; 1× is selected and the original three session directories were preserved.

Final package: `/tmp/april-fools-final-ee60e20/AprilFoolsAR.app`, version 0.1.3 build 8, source `ee60e2021e2ba9cd7a5cc83d4c83b3b66b2dffef`, built `2026-11-22T00:02:22Z`, with no uncommitted source changes. The Release build, strict/deep signature check and metadata comparisons passed. Build log: `/tmp/april-fools-status-row-build.log`.

Executable SHA-256: `b83131e2dcfca795d96f3241e2a64d58d1448b619aafc2299275a9862845a46e`. Debug symbols are retained locally under ignored `crash-reports/2026-11-21/build8-ee60e20/`.

Device screenshot: `/tmp/april-fools-ar-ee60e20-status-row.png`. Detector telemetry continued around 30 Hz. No recordings or settings changes were made during this layout check.
