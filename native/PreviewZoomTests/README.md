# Display zoom geometry regression

Run the production `PreviewZoom` helper and `AprilTagOverlayView` in an isolated UIKit simulator host:

```sh
ruby native/PreviewZoomTests/run-zoom-tests.rb
```

Optional `--device-id ID` chooses a simulator and `--work-dir DIR` retains the generated project/build/xcresult at a selected temporary location. Default device is iPhone 17 (`DBE3B4F0-0581-4B4F-B693-17FEC5753C55`). Product sources are referenced directly; no live ARSession or camera is instantiated.

The five tests cover independently calculated centered 1×/2×/4× points and inverses in portrait/landscape viewports, noncommuting base-transform composition, continuous clamping and invalid-input handling, actual tag polygon selection at zoomed screen locations, and UIKit's inverse coordinate conversion for measurement taps. They verify the unscaled overlay/raw view bounds remain unchanged. Test inputs are synthetic geometry, not physical measurement evidence.

Production integration is reviewed separately: `ARCaptureView.layoutSubviews` assigns camera/depth **bounds and center**, rather than setting a transformed view's frame; only their display transforms change. The overlay stays in full, unscaled viewport bounds and receives the composed base-plus-zoom transform. `tapped` requests measurement coordinates in `arView`, so UIKit removes display scaling before the coordinator applies the original ARKit display transform inverse. The passed zoom is metadata only, avoiding a second inverse. Source image dimensions, camera intrinsics, camera poses and raw `displayTransform` remain unchanged; `previewDisplayTransform` is recorded separately.

The companion React Native tests in `__tests__/App.test.tsx` verify all presets call native code, the displayed zoom follows native acknowledgement, and continuous native pinch status updates reach the UI without issuing another preset request. Device pinch behavior and camera/overlay alignment still require the separate phone check.
