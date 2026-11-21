# View zoom

Version 0.1.2 (build 7) adds centered 1×–4× live-preview magnification through pinch and 1×/2×/4× buttons. The label explicitly says **View**. The AR camera, sensor samples, intrinsics and pose solver retain their original capture configuration.

The camera/depth previews magnify together. The tag overlay projects through the same centered zoom while retaining readable label sizes. Measurement input converts back through the view transform before the existing image/depth mapping. The native diagnostic panel and React Native controls do not scale.

## Checks

- [x] Native zoom bounds, forward/inverse mapping, display-transform composition and interaction checks: five UIKit tests pass, including actual tag hit paths and inverse measurement coordinates at 1×/2×/4× in portrait and landscape. Source review confirms unchanged raw camera bounds/calibration and separate preview geometry.
- [x] React Native preset command and native-status update checks: all 15 app tests pass, including all presets, waiting for native acknowledgement and continuous pinch-status display. TypeScript and ESLint pass.
- [x] Signed exact-revision build and bundled release/build identity checks.
- [x] Device Hub installation, version/launch check and observed 1×/4× display states.
- [ ] Complete on-device 2×/return-to-1× and mode-switch interaction checks.
- [ ] Physical multitouch pinch and real-tag/measurement alignment checks.

This is view magnification, not optical zoom or camera switching. It does not establish improved measurement accuracy or extend detection range.

Native reproduction: `ruby native/PreviewZoomTests/run-zoom-tests.rb --work-dir /tmp/aprilfools-preview-zoom-20261121`. Results are retained in that directory's `Results.xcresult`. JavaScript checks: `npx tsc --noEmit`, `npm run lint -- --quiet`, and `npm test -- --runInBand`.

## Final package

- Version 0.1.2, build 7; full source `31ead9f09fb9272417d4b66b3f02536cd8ecb6cb`.
- Built `2026-11-21T23:54:32Z` with `workingTreeDirty=false`.
- Package `/tmp/april-fools-final-31ead9f/AprilFoolsAR.app` passes strict/deep code-signature checks and embedded identity checks. Build log: `/tmp/april-fools-zoom-final-build.log`.
- Executable SHA-256 `d305fa0f05b6d280320241019d35ba9b7d0037daf296ae75e6778ab42ec0048b`.
- Symbol UUID `D9ACA1C7-0F0B-3E29-994A-04125B8089AA`; local dSYM retained in ignored `crash-reports/2026-11-21/build7-31ead9f/`.

## Device observation

Installed in place through Device Hub on Doug's iPhone 17 Pro. The header displays `v0.1.2 (7) · 31ead9f`; the app remains running as PID 6463. The initial `View 1.0×` state and final `View 4.0×` / selected 4× button were visible, with the diagnostic panel and viewport boundaries unchanged. Detector telemetry continued around 30 Hz.

Further coordinate taps returned Device Hub `windowNotFoundAtPosition`, so automation stopped. The 2×/return-to-1× and mode-switch checks were not completed; final zoom stayed at 4×. The mirrored RGB image was black and no tag was visible, so this observation does not verify physical image/axis alignment or pinch. The native tests above verify the coordinate conversions and all preset values.

Screenshots: `/tmp/april-fools-ar-31ead9f-1x.png` and `/tmp/april-fools-ar-31ead9f-final.png`. Three existing session directories were preserved; no recording or camera configuration was changed during validation.
