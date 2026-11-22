# Shared core iPhone handoff — 0.6.1 (20)

November 22, 2026: installed and launched on Doug's iPhone 17 Pro.

- Signed clean source: `4d359a06bcbed57fe84dd86d3697327836c5699f`.
- Build date: `2026-11-22T21:26:11Z`; version/build: `0.6.1 (20)`.
- Retained the existing application identifier for an in-place update. Device installation metadata confirmed the expected version and build. The Documents directory listing was unchanged before and after installation.
- Device Hub showed the live app with matching version/hash, normal tracking, Depth Live and approximately 30 Hz tag analysis. No physical tag or known-distance measurement was evaluated during this handoff.
- No recording was started or deleted. The user performs field/measurement acceptance and returns the original exported MP4 for replay review.
- Screen sharing was explicitly stopped. A fresh window inventory showed one Device Hub window, with View Screen enabled, Capture Keyboard off and no live-view controls. The global device guard verified this evidence and returned `released` with no errors. Owned deployment commands exited; no test runner remains attached.

Suggested user checks: confirm a floor, compare tag height and camera distances while moving/zooming, test reacquisition after a tag leaves view, then record and export the original MP4. SC.T and the M0 real-field/review gate remain open until their actual evidence is available.

Private raw deployment and release evidence is retained under `/tmp/afsc-iphone-handoff/`; tokens and device identifiers are not committed.
