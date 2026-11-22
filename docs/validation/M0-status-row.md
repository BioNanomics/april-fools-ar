# Single-line camera status and zoom

Version 0.1.3 (build 8) combines tracking status, depth status, the current view magnification and the 1×/2×/4× buttons into one 44-point-high translucent row. The separate second zoom row is removed. Status text stays on one line and can shrink slightly for longer status messages; zoom buttons retain their existing touch targets and behavior.

The change affects the React Native layout only. Camera geometry, raw data, pose/depth calculations and native pinch handling retain the behavior verified in [M0-view-zoom.md](M0-view-zoom.md).

- [x] TypeScript, lint and all 15 existing app tests pass.
- [ ] Signed exact-revision build and identity checks.
- [ ] Device Hub installation and visual check that status and zoom fit on one line.
