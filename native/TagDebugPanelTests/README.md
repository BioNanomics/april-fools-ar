# Debug panel readability regression

This standalone UIKit/XCTest host compiles the real `TagDebugPanelView.swift` and `TagDebugMath.swift`. Synthetic debug records exist only in this test bundle. It does not launch ARKit, simulate physical accuracy, or add any product demo behavior.

From the repository root, with the same Ruby/xcodeproj environment used by the iOS configuration scripts:

```sh
ruby native/TagDebugPanelTests/run-uikit-panel-regression.rb
```

Optional `--device-id` selects a simulator, `--work-dir` retains a named build directory, and `--only-testing TARGET/CLASS/METHOD` reruns a focused case. Default simulator: iPhone 17, `DBE3B4F0-0581-4B4F-B693-17FEC5753C55`.

Checks cover actual displayed values, a 390×270-point panel, row/label bounds, text fit including both footer lines, independent green/amber/red depth-difference colors and threshold tolerance, no-tag live telemetry, and reuse of view/label/layer identities over 600 updates. Valid, ambiguous-with-missing-depth, neutral missing-depth and unavailable screenshots use UIKit `drawHierarchy(afterScreenUpdates:true)`, are attached to the xcresult, and are copied to the printed `/tmp/.../artifacts` directory. Images render at 3× pixel density (1170×810 pixels).

Do not include this directory in the product app target. The harness creates its project/build/results in a temporary directory and changes no product sources. Passing synthetic layout tests does not replace physical-device or camera validation.
