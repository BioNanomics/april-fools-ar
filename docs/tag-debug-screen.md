# AprilTag debug screen

The debug screen compares two estimates from the same AR camera frame: the pose solved from the tag corners and configured tag width, and ARKit's scene-depth sample at the tag center. Agreement is a useful diagnostic; it does not establish surveyed field accuracy.

## Using it

**Tag debug** is the default live view. The camera fills the available preview area; the debug readout floats over it instead of reserving a separate panel below it. The compact translucent overlay shows the selected tag's validity, pose Z, LiDAR Z, colored difference and live timing. Tap **Details** for translation, orientation, angles, range and decoder quality; tap **Collapse** to return to the compact view. Expanding does not crop, resize or change the camera's projection.

Tag outlines, four corner points and IDs remain on the camera image. Tap a tag to inspect it; otherwise the view chooses a tag near the image center. Only the Details/Collapse button consumes overlay touches; the remaining overlay area allows tag selection beneath it. **Measure** returns to the two-point distance/vertical-difference probe.

Enable **Show pose axes** in Settings and apply the change to draw a tag-centered pose gizmo: red **X**, green **Y**, blue **Z**. The axes use the solved tag-to-camera pose and the same frame's camera intrinsics, then the same image-to-screen transform as the tag corners. Each axis is half a tag width long. These are tag-local axes, not gravity or field axes; a direction pointing toward/away from the camera can appear foreshortened. The option defaults off and is saved on the phone.

**View zoom:** pinch anywhere on the live image or use **1× / 2× / 4×**. Magnification is centered and limited to 1×–4×. The camera and depth previews zoom together; tag corners and axes use the matching screen transform, and measurement taps map back into the original image coordinates. The readout and controls remain their normal size. This changes the display only: it does not select another lens, add image detail, or change recorded sensor samples and solved poses.

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
