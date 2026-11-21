# View zoom

Version 0.1.2 (build 7) adds centered 1×–4× live-preview magnification through pinch and 1×/2×/4× buttons. The label explicitly says **View**. The AR camera, sensor samples, intrinsics and pose solver retain their original capture configuration.

The camera/depth previews magnify together. The tag overlay projects through the same centered zoom while retaining readable label sizes. Measurement input converts back through the view transform before the existing image/depth mapping. The native diagnostic panel and React Native controls do not scale.

## Checks

- [x] Native zoom bounds, forward/inverse mapping, display-transform composition and interaction checks: five UIKit tests pass, including actual tag hit paths and inverse measurement coordinates at 1×/2×/4× in portrait and landscape. Source review confirms unchanged raw camera bounds/calibration and separate preview geometry.
- [x] React Native preset command and native-status update checks: all 15 app tests pass, including all presets, waiting for native acknowledgement and continuous pinch-status display. TypeScript and ESLint pass.
- [ ] Signed exact-revision build and bundled release/build identity checks (preliminary signed build passes).
- [ ] Device Hub installation and 1×/2×/4× display checks.
- [ ] Physical multitouch pinch and real-tag/measurement alignment checks.

This is view magnification, not optical zoom or camera switching. It does not establish improved measurement accuracy or extend detection range.

Native reproduction: `ruby native/PreviewZoomTests/run-zoom-tests.rb --work-dir /tmp/aprilfools-preview-zoom-20261121`. Results are retained in that directory's `Results.xcresult`. JavaScript checks: `npx tsc --noEmit`, `npm run lint -- --quiet`, and `npm test -- --runInBand`.
