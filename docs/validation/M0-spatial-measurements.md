# Floor planes and persistent spatial measurements

Version 0.2.0 (build 9) adds explicit floor selection and world-space measurement overlays to the Milestone 0 capture app. It does not add field calibration or a surveyed floor reference.

- [x] Native math, state transitions, clipping/projection and overlay lifecycle: 15 simulator tests passed with zero failures. The suite uses the production model/projection/UIView renderer, including native accessibility labels and expiry when camera callbacks stop, and a dedicated April Fools Spatial Tests simulator. Result bundle: `/tmp/aprilfools-spatial-expiry-20261122/Results.xcresult`.
- [x] React Native workflow tests: 20/20 passed, including saved-height readouts and the isolated AR tag-width workflow. TypeScript, ESLint and whitespace checks passed.
- [x] Signed Release build with verified version, full source revision and build date. Version **0.2.0 (9)**, source `d08a7b868aad3057ca06822eabf3a2136a9e7958`, built `2026-11-22T15:39:38Z`, clean source tree. Strict/deep signature and embedded build metadata comparisons passed.
- [x] Device Hub in-place install/launch on Doug's iPhone 17 Pro (`00008150-001209063CB9401C`). Installed version/build verified through `devicectl`; the app was running as PID `9311` after launch. All three original session directories were retained. View Screen remained inactive; no mirroring, WDA, XCTest or Appium runner was started. Deployment commands exited and device release was verified before documentation/push.
- [ ] Tester floor selection, parallax/zoom, interruption and saved-recording checks on a real floor.

In **Measure**, enable **Floor on** to see detected horizontal surfaces. Use **Set floor** and tap the actual floor boundary to confirm the datum. **Floor height** then accepts a target tap with usable LiDAR depth and draws a vertical segment down to that floor. **Two points** draws a segment between two accepted depth taps. The graphics are projected from stored world coordinates every camera frame, rather than fixed to screen pixels.

Completed measurements retain their original endpoints and values while moving through the same AR coordinate segment. Multiple measurements can remain visible. Clearing measurements retains the confirmed floor. Measuring a tag width uses a separate temporary pair and leaves the measurement history intact.

Limited tracking hides world overlays and prevents new measurements until normal tracking returns. A new coordinate segment (including reset, interruption, background or view detach) invalidates live geometry. Recorded measurements remain in the recording. This release saves data for review but does not relocalize saved measurements after restarting the app.

Measurements are AR/LiDAR estimates. Selecting a floor confirms the user's intended surface; it does not establish physical accuracy. The real-floor checks remain with the tester in [T0.1e](../../TESTER_CHECKLIST.md).

The complete native capture integration also passed `swiftc -typecheck` against the iOS 27.2 SDK. Existing weak-capture/deprecated-plane-extent warnings remain; no compiler errors. Source-level review verifies recording-start snapshots retain completed geometry while clearing only pending taps, stop preserves live geometry, limited tracking clears pending taps only, and coordinate-segment changes invalidate live placement.

Before this update’s physical phase, the prior task-owned Device Hub screen sharing was explicitly stopped and verified through the return to **View Screen**. No task-owned Appium, WebDriverAgent or XCTest phone runners were started.

Final package: `/tmp/april-fools-final-d08a7b8/AprilFoolsAR.app`. Build log: `/tmp/april-fools-spatial-build.log`. Executable SHA-256: `70801f7d6a07fc315fc4b5596e80e5b0591f481fd311a8a0c9f16c2d9b4e3d8d`. Debug symbols are retained locally under ignored `crash-reports/2026-11-22/build9-d08a7b8/`.

The physical handoff verifies installation and launch only. The tester still needs to confirm real-floor detection, measurement alignment while walking, and returned capture data; no physical accuracy claim is made by the simulator checks.
