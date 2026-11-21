# AprilTag debug screen

The debug screen compares two estimates from the same AR camera frame: the pose solved from the tag corners and configured tag width, and ARKit's scene-depth sample at the tag center. Agreement is a useful diagnostic; it does not establish surveyed field accuracy.

## Using it

**Tag debug** is the default live view. Tag outlines, four corner points and IDs remain on the camera image. Tap a tag to inspect it; otherwise the view chooses a tag near the image center. The native panel displays the selected tag's pose, LiDAR depth, mismatch, angles, quality and validity. **Measure** returns to the two-point distance/vertical-difference probe.

Open **Settings** to edit:

| Setting | Initial value |
| --- | --- |
| Physical tag width | 165.1 mm / 6.5 inches |
| Maximum range | 5 m |
| Maximum plane incidence angle | 60° |
| Depth mismatch warning | 10 cm |
| Depth mismatch rejection | 15 cm |
| Maximum corner reprojection RMS | 3 pixels |

Tag width is the distance between the detection corners at the black/white border, not the outside of the paper. This is the size definition used by [the upstream pose estimator](https://github.com/AprilRobotics/apriltag#pose-estimation). The FRC default follows [WPILib's tag description](https://docs.wpilib.org/en/stable/docs/software/vision-processing/apriltag/apriltag-intro.html).

You can type a measured width or choose **Measure tag width with AR**. For an AR estimate, tap two adjacent boundary corners on one physical tag edge. Review the resulting distance and press **Use width** to apply it. Cancel leaves the configured width unchanged. The estimate comes from the existing AR/LiDAR endpoint measurements, not from a pose already scaled by the configured width. It remains sensitive to tap placement, depth resolution and tracking error, so a carefully measured physical width is preferable when available.

## Coordinate and quality definitions

- Camera translation uses optical coordinates: **+X right, +Y down, +Z forward**, in meters. These differ from ARKit's +Y-up / −Z-forward camera convention.
- These axes refer to the captured sensor image before the UI's portrait rotation/cropping. Roll/pitch/yaw are camera-relative tag orientation, not compass or gravity-referenced phone attitude.
- The solver uses the matching ARKit intrinsics with a zero-skew pinhole model; it does not apply a separately measured lens-distortion calibration.
- Rotation is the tag-to-optical-camera matrix. Displayed angles use **R = Rz(yaw) Ry(pitch) Rx(roll)**, in degrees. The matrix is authoritative near Euler singularities.
- **Pose Z** is forward camera-plane depth. **Range** is the Euclidean length of the translation vector. They differ for a tag away from the image center.
- **LiDAR center** is the matching-frame scene-depth sample at the detected tag center. The separate small-neighborhood mean includes only finite, positive, accepted-confidence samples; it does not silently replace a missing center sample.
- **Depth difference** is `abs(LiDAR center − pose Z)`. Green is at/below the warning threshold, amber is above warning through rejection, and red is above rejection. Missing or unusable data is neutral, not green.
- **Plane angle** is the angle between the tag-plane normal and the line of sight: 0° is head-on, 90° is edge-on. It drives the angle gate. **Center bearing** is the angle of the translation vector away from the optical axis and is shown separately.
- **Reprojection RMS** is calculated in image pixels from the four projected tag corners. The upstream solver's object-space error is a different quantity and is retained separately.
- **Decision margin** and corrected-bit count are raw decoder diagnostics, not a confidence percentage. A near-equal, distinct second pose is marked ambiguous. Missing pose/depth, low confidence, limited tracking, excessive range/angle, poor fit and mismatch get explicit reasons.

## Timing and records

The camera is configured for 30 Hz. Detection and pose estimation use one worker with one frame in flight; a busy worker drops incoming work instead of queuing old frames. The prior fixed 8 Hz analysis throttle is removed. The native overlay/panel uses current results directly; React Native receives only bounded status updates and manages settings. Actual analysis rate, latency and result age are shown rather than assuming that the device always achieves 30 analyses per second.

Each analyzed frame's event retains the calibration, tag width/settings, optical pose, quality diagnostics and synchronized depth samples. Changing settings invalidates results computed under the old settings. Accepted AR width estimates retain the endpoint and frame provenance. Original RGB, numeric depth/confidence and AR camera metadata continue to be recorded for later review.

The iPhone test should include a centered tag, an off-axis tag, a steeply angled tag, increasing distance, unavailable/low-confidence depth, and both sides of the mismatch thresholds. It should also check sustained actual analysis rate, stale-value clearing, size changes, repeated tag appearance/disappearance and export readability. These checks do not replace the later independent accuracy evaluation.
