# Guided floor setup before measurements

Version 0.3.1 (build 13) starts Measure with a guided floor scan whenever the current AR segment has no confirmed floor. The user moves around to extend the detected plane, checks the highlighted candidate and presses **Done** before measuring. A classified floor can be selected automatically; an unclassified surface requires a tap. Tapping a plane alone no longer confirms it.

Done requires a current, normal-tracking candidate covering at least 1.00 m² with a minimum horizontal span of 0.50 m. These are scan-coverage gates, not an independently validated accuracy claim. The candidate continues refining until Done freezes the latest snapshot. Existing confirmed floors can be reused in the same segment; Change floor or a coordinate reset opens setup again.

- [x] Native candidate lifecycle, coverage and measurement-bypass tests: 13/13 model cases passed, including all manual modes, live refinement, frozen confirmation, lost/replaced candidates, tracking and rotated narrow-strip rejection.
- [x] React Native floor-first entry, guidance, Done and tag-width handoff tests: full suite 27/27 passed. TypeScript and ESLint passed.
- [x] Native pending/confirmed floor rendering and lifecycle checks: 9/9 UIKit projection/renderer cases passed. Combined native result: `/tmp/aprilfools-floor-first-state-final-20261122/Results.xcresult`. The dedicated simulator was shut down after the run.
- [x] Signed exact-revision Release build and metadata verification: **0.3.1 (13)**, source `f1a95245c8ff2fed94ab4d462ab37f62f3f559f3`, built `2026-11-22T17:47:28Z` from a clean source tree. Strict/deep signature and embedded version/commit/build-date comparisons passed.
- [x] Guarded Device Hub in-place install and launch on Doug's iPhone 17 Pro. Installed version/build and running process independently verified; all three original session directories retained. No new recording, remote capture, WDA, XCTest or Appium runner was started. Fresh full-window evidence verified capture inactive; the global guard returned `released` with no errors before repository work resumed.
- [ ] Tester checks on the real floor in T0.1i.

Recording can capture the scan itself. During setup, manual probes and measurement overlays are inactive; stored measurements retain their original geometry. Automatic floor-height readouts do not use an unconfirmed candidate. Camera-range diagnostics retain their independent source-frame calculations.

The scan uses the RGB preview with floor boundaries visible, including after a coordinate reset. The selected candidate is amber and dashed; confirmation changes it to the frozen cyan floor datum. A Done request includes the displayed candidate ID, so a disappearing or replaced plane must be reviewed again. Candidate selection and final confirmation are recorded separately, with scan coverage attached to the confirmation event.

Native integration review covered current-segment floor references, camera/floor presentation after reset, stale callback rejection and temporary suppression of automatic floor-height estimates. The complete native integration compiled in the signed Release build. Actual floor acquisition and measurement behavior remain the tester's T0.1i check.

Final package: `/tmp/april-fools-final-f1a9524/AprilFoolsAR.app`. Build log: `/tmp/april-fools-floor-setup-build.log`. Executable SHA-256: `2e4912876259a47947ba91fa2945699fc03285019e4e800b5f0849250615c088`. Debug symbols are retained locally under ignored `crash-reports/2026-11-22/build13-f1a9524/`.
