# Debug panel readability regression

This standalone UIKit/XCTest host compiles the real `TagDebugPanelView.swift` and `TagDebugMath.swift`. Synthetic debug records exist only in this test bundle. It does not launch ARKit, simulate physical accuracy, or add any product demo behavior.

From the repository root, with the same Ruby/xcodeproj environment used by the iOS configuration scripts:

```sh
ruby native/TagDebugPanelTests/run-uikit-panel-regression.rb
```

Optional `--device-id` selects a simulator, `--work-dir` retains a named build directory, and `--only-testing TARGET/CLASS/METHOD` reruns a focused case. Default simulator: iPhone 17, `DBE3B4F0-0581-4B4F-B693-17FEC5753C55`.

Checks cover the **default 390×96-point translucent overlay**, its PnP/LiDAR/delta/timing readout, and its explicit Details button. Tests verify a button target of at least 44 points, camera-touch passthrough everywhere else, expansion/collapse and preferred-height callbacks. Full metric tests explicitly expand to 390×270 points and check row/label bounds, text fit including both footer lines, independent green/amber/red depth-difference colors and threshold tolerance, no-tag live telemetry, and reuse of view/label/layer identities over 600 updates. Long `TAG #587 · POSE UNAVAILABLE` and `TRACKING LIMITED` titles are checked and captured in both modes.

Compact valid/no-tag and expanded valid/ambiguous/missing-depth screenshots use UIKit `drawHierarchy(afterScreenUpdates:true)`, are attached to the xcresult, and are copied to the printed `/tmp/.../artifacts` directory. Images render at 3× pixel density (1170×288 for compact, 1170×810 for expanded). The test-only navy backdrop demonstrates translucency without adding fake camera imagery to the product.

The component test verifies expansion does not resize its host. The production viewport contract is also reviewed directly in `ARCaptureView.layoutSubviews`: `arView`, `depthView` and `tagOverlay` receive full `bounds`, only the floating panel uses `preferredHeight`, and the capture viewport uses `arView.bounds`. The host tap recognizer excludes UIControl touches, allowing the Details button to own its tap. This harness deliberately does not instantiate a live ARSession or claim a simulator camera test.

Do not include this directory in the product app target. The harness creates its project/build/results in a temporary directory and changes no product sources. Passing synthetic layout tests does not replace physical-device or camera validation.
