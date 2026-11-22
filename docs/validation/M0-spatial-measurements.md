# Floor planes and persistent spatial measurements

Version 0.2.0 (build 9) adds explicit floor selection and world-space measurement overlays to the Milestone 0 capture app. It does not add field calibration or a surveyed floor reference.

- [x] Native math, state transitions, clipping/projection and overlay lifecycle: 14 simulator tests passed with zero failures. The suite uses the production model/projection/UIView renderer, including native accessibility labels, and a dedicated April Fools Spatial Tests simulator. Result bundle: `/tmp/aprilfools-spatial-regression-20261122/Results.xcresult`.
- [x] React Native workflow tests: 20/20 passed, including saved-height readouts and the isolated AR tag-width workflow. TypeScript, ESLint and whitespace checks passed.
- [ ] Signed Release build with verified version, full source revision and build date.
- [ ] Brief Device Hub install/launch check and physical automation cleanup.
- [ ] Tester floor selection, parallax/zoom, interruption and saved-recording checks on a real floor.

In **Measure**, enable **Floor on** to see detected horizontal surfaces. Use **Set floor** and tap the actual floor boundary to confirm the datum. **Floor height** then accepts a target tap with usable LiDAR depth and draws a vertical segment down to that floor. **Two points** draws a segment between two accepted depth taps. The graphics are projected from stored world coordinates every camera frame, rather than fixed to screen pixels.

Completed measurements retain their original endpoints and values while moving through the same AR coordinate segment. Multiple measurements can remain visible. Clearing measurements retains the confirmed floor. Measuring a tag width uses a separate temporary pair and leaves the measurement history intact.

Limited tracking hides world overlays and prevents new measurements until normal tracking returns. A new coordinate segment (including reset, interruption, background or view detach) invalidates live geometry. Recorded measurements remain in the recording. This release saves data for review but does not relocalize saved measurements after restarting the app.

Measurements are AR/LiDAR estimates. Selecting a floor confirms the user's intended surface; it does not establish physical accuracy. The real-floor checks remain with the tester in [T0.1e](../../TESTER_CHECKLIST.md).

The complete native capture integration also passed `swiftc -typecheck` against the iOS 27.2 SDK. Existing weak-capture/deprecated-plane-extent warnings remain; no compiler errors. Source-level review verifies recording-start snapshots retain completed geometry while clearing only pending taps, stop preserves live geometry, limited tracking clears pending taps only, and coordinate-segment changes invalidate live placement.

Before this update’s physical phase, the prior task-owned Device Hub screen sharing was explicitly stopped and verified through the return to **View Screen**. No task-owned Appium, WebDriverAgent or XCTest phone runners were started.
