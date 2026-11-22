# Spatial measurement regressions

This isolated UIKit test host compiles the actual production state, projection,
renderer, and display-zoom helper. It creates no ARSession and uses no phone.

Run with an explicitly selected, task-owned iPhone simulator:

```sh
ruby native/SpatialMeasurementTests/run-spatial-tests.rb \
  --device-id YOUR_APRIL_FOOLS_SIMULATOR_UUID \
  --work-dir /tmp/aprilfools-spatial-regression
```

The host writes `Results.xcresult` and `xcodebuild.log` in that directory.
Tests cover plumb intersection with horizontal/sloped planes, invalid evidence,
floor confirmation, immutable completed records and source provenance, tracking
versus segment lifetime, non-destructive count limits, AR-width isolation, camera
pose inversion, asymmetric intrinsics, portrait/zoom projection, near-plane and
viewport clipping, floor hit paths, passive touch handling, accessibility labels,
bounded renderer pools, and reuse/owned cleanup.
An expiry regression also verifies that labels, vector/plane layers, and floor hit
paths disappear after their deadline when no further camera callback arrives.

Every manual-mode fixture completes the floor scan with an explicit Done action
before adding points. Floor-first cases cover provisional selection, stable
automatic choice and manual override, live candidate refinement, 1 m² coverage,
rotation-invariant 0.5 m minimum width, stale/limited/foreign or lost candidates,
the expected-candidate-ID race guard, requested-mode restoration, and the frozen
confirmed datum. The UIKit test distinguishes provisional dashed candidates from
the confirmed floor without rebuilding its render slot.

Fixtures validate geometry and lifecycle rules; they do not establish physical
LiDAR, tracking, floor-detection, or field accuracy.
