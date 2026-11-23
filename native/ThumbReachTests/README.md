# Actual-app navigation and thumb reach checks

Build a simulator Release app, then run:

```sh
ruby native/ThumbReachTests/run-thumb-reach.rb \
  --app-path /tmp/april-thumb-sim-build/Build/Products/Release-iphonesimulator/AprilFoolsAR.app
```

The harness creates a dedicated iPhone simulator, installs the supplied product,
and queries the actual app's native accessibility tree. Expected version/build
values come from the supplied app's `Info.plist`. It saves full-screen native
screenshots, frame logs and navigation hierarchy attachments, then terminates the
app and shuts down/deletes its own simulator. It never attaches to a physical
phone or an existing simulator.

Use `--work-dir DIR` for a fresh named output directory. The optional
`--derived-data-path DIR` reuses a previous harness build cache while keeping
results separate. Full-screen XCTest screenshots preserve rotation correctly;
app-scoped screenshots can crop rotated simulator content.

The checks cover:

- Portrait lower-half controls and landscape right-side navigation, Kalman, zoom,
  recording, Details, measurement, More, name and Saved panels, including React
  Native controls exposed as `Other`. Landscape panels use the available height
  below the version badge instead of occupying the lower half.
- All primary capture controls are hittable with at least 44-point touch targets.
  Both landscape directions are tested; returning to portrait retains zoom and
  returns the controls to the lower half.
- The explicitly allowed upper-right version button, its exact version/build
  accessibility value and its minimum 44-point touch target.
- Full-screen Version and About bounds, substantial reading viewports, and
  hittable bottom navigation contained in the footer. Scrollable information
  links may appear above the midpoint.
- Badge and More entry to Version, Version/Release notes tab changes, local
  badge reset to Version, and return to the original Saved view.
- Unified About/sponsors content, Privacy/Licenses navigation, and native
  Settings/About dismissal followed by queued Version presentation.

Fabric exposes footer test IDs as accessibility leaves beside their tabs.
Navigation queries therefore require exact-label candidates to be hittable and
fully contained in the footer's native frame; they do not assume accessibility
parent/child ancestry or confuse upper headings with bottom tabs.

Verified on 2026-11-23 with product **0.11.0 (31)** and iPhone 17 / iOS 26.0:
**3 tests passed, 0 failures**, in portrait and both landscape directions
(462 seconds). On the 874 × 402-point landscape screen, the capture rail is
330 × 294 points at x474/y80; Settings is 344.7 × 294 points at x451.3/y80.
Both panels clear the version badge and keep visible controls on the right.
All primary capture actions remain hittable with at least 44-point touch targets.
Both landscape-to-portrait returns preserve the selected zoom and restore bottom
controls. Full-screen Version/About navigation and queued modal handoffs also
pass in all three orientations.

The current run's 26 PNGs, full frame logs and result bundle are under
`/tmp/april-landscape-ui-tests`. Capture screenshots in both landscape directions,
landscape Settings and portrait capture were visually checked. The harness exited
and final `simctl` inventory independently confirmed its dedicated simulator was
deleted. No physical-device actions were used for these UI checks.

Earlier full-screen navigation baseline, verified on 2026-11-23 with product **0.10.0 (30)** and iPhone 17 / iOS 26.0:
**2 tests passed, 0 failures**, in portrait (402 × 874 points) and landscape
(874 × 402 points). Both queued native Modal transitions passed in both
orientations. Full-screen opaque appearance was visually checked in the native
screenshots. The successful run's 16 PNGs, logs and result bundle are under
`/tmp/april-fullscreen-info-ui-tests-v3`. All owned test simulators were deleted.

These tests use no synthetic AR detections. They verify navigation, native
accessibility exposure and layout; live tag taps, camera/LiDAR behavior and floor
retention still require hardware verification.
