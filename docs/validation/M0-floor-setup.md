# Guided floor setup before measurements

Version 0.3.1 (build 13) starts Measure with a guided floor scan whenever the current AR segment has no confirmed floor. The user moves around to extend the detected plane, checks the highlighted candidate and presses **Done** before measuring. A classified floor can be selected automatically; an unclassified surface requires a tap. Tapping a plane alone no longer confirms it.

Done requires a current, normal-tracking candidate covering at least 1.00 m² with a minimum horizontal span of 0.50 m. These are scan-coverage gates, not an independently validated accuracy claim. The candidate continues refining until Done freezes the latest snapshot. Existing confirmed floors can be reused in the same segment; Change floor or a coordinate reset opens setup again.

- [x] Native candidate lifecycle, coverage and measurement-bypass tests: 13/13 model cases passed, including all manual modes, live refinement, frozen confirmation, lost/replaced candidates, tracking and rotated narrow-strip rejection.
- [x] React Native floor-first entry, guidance, Done and tag-width handoff tests: full suite 27/27 passed. TypeScript and ESLint passed.
- [x] Native pending/confirmed floor rendering and lifecycle checks: 9/9 UIKit projection/renderer cases passed. Combined native result: `/tmp/aprilfools-floor-first-state-final-20261122/Results.xcresult`. The dedicated simulator was shut down after the run.
- [ ] Signed exact-revision Release build and metadata verification.
- [ ] Guarded iPhone install/launch and verified device release.
- [ ] Tester checks on the real floor in T0.1i.

Recording can capture the scan itself. During setup, manual probes and measurement overlays are inactive; stored measurements retain their original geometry. Automatic floor-height readouts do not use an unconfirmed candidate. Camera-range diagnostics retain their independent source-frame calculations.

The scan uses the RGB preview with floor boundaries visible, including after a coordinate reset. The selected candidate is amber and dashed; confirmation changes it to the frozen cyan floor datum. A Done request includes the displayed candidate ID, so a disappearing or replaced plane must be reviewed again. Candidate selection and final confirmation are recorded separately, with scan coverage attached to the confirmation event.
