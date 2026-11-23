# AprilTag debug screen

The debug screen compares two estimates from the same AR camera frame: the pose solved from the tag corners and configured tag width, and ARKit's scene-depth sample at the tag center. Agreement is a useful diagnostic; it does not establish surveyed field accuracy.

## Using it

**Tags** is the default live view. The camera fills the screen behind a compact control dock. In portrait, all primary controls occupy its lower half: **Tags / Measure / Saved / Details / More**, then **Kalman / zoom / Settings**, then **Name / Record / Bookmark**. Small live cards show every detected tag's floor height and an aligned **Distance** comparison for **LiDAR** and **Tag**. These are straight-line camera-to-tag-center distances, including horizontal/vertical offset. **LiDAR Δ** appears only when their absolute difference exceeds **Settings → Distance delta threshold (cm)** (15 cm by default). Missing estimates do not produce a delta. Tap a detected tag or open **Details** in the dock for translation, orientation, raw pose/LiDAR Z, their difference, angles, distance and decoder quality in a scrollable tool panel. Opening tools does not crop, resize or change the camera's projection.

Tag outlines, four corner points and IDs remain on the camera image. Tap a tag to select it and open its details panel; otherwise the view chooses a tag near the image center without opening a panel. Tapping the same tag again reopens details after closing it. The upper readouts are passive. **Measure** opens floor selection and manual distance/height tools in a lower-half scroll panel, with recording controls pinned below it. **Done** closes a tool panel; tap **Measure** again to reopen its controls. **More** stays a lower-half panel and contains About & sponsors and version/release notes. About and Sponsors share one full-screen page with About, Privacy, Licenses and Done navigation along the bottom. The version badge stays visible in the upper right and is tappable; it and More open the same full-screen Version page, with Version, Release notes and Done along the bottom. In landscape, capture controls and tools move to a right-side panel below the version badge, clear of the camera cutout and home indicator. Navigation wraps into a compact grid, Kalman and Settings share a row, zoom has its own row, and Record stays pinned below the scrollable tools. Measurement, Details, More, Name and Saved use the same side panel; Settings also opens on the right with pinned Cancel/Apply actions. In portrait, these panels remain in the lower half. Rotating retains the camera, current recording, floor/tool selection, zoom and settings draft.

**Automatic floor height:** enter Measure and scan the floor. A classified floor can be highlighted automatically; tap the correct floor if needed. Press **Done** when coverage and tracking are ready, then return to Tag debug. Every usable detected tag shows its estimated center height beside its ID without a per-tag tap. The selected-tag readout identifies **LiDAR** or **Pose** as the source. LiDAR uses the accepted depth at the detected center; the pose fallback depends on the configured physical tag width. Height is vertical above the confirmed floor plane, including when that plane is slightly sloped. These are estimates, not independently verified physical dimensions. Missing/invalid input displays an unavailable height, and resetting the AR coordinate segment requires selecting the floor again. Automatic tag heights do not create persistent manual measurement vectors.

Each usable tag also gets a live world-space height vector from its floor intersection to the tag center, with the height label halfway along the vector. It remains vertical with gravity, even if the detected floor is slightly tilted. These live vectors reproject as the camera moves and clear when their source detection expires, tracking is lost or the floor changes. Existing manually saved measurements retain their separate persistence.

A small dotted 30 cm square marks each height vector's floor foot. It follows the active measurement floor: green for level (within 0.5°), yellow for tilted, and neutral gray when tilt is unavailable. Gravity leveling makes the reference horizontal and green. Saved manual height vectors keep the floor reference used when they were measured.

The camera view shows the **detected floor tilt** in degrees from horizontal. The estimate comes from a robust fit to usable LiDAR samples across the selected floor; insufficient coverage or inconsistent depth shows **tilt unavailable**. ARKit's horizontal plane anchors are already constrained to be level, so their rotation alone cannot establish physical floor tilt. **Settings → Level floor with gravity** is off by default. Turning it on uses a horizontal measurement plane at the selected floor's center elevation; the original tilt remains visible. Turning it off restores the detected floor plane. Apply the setting to change the current reference and save the preference. Completed manual measurements keep their original floor and values. During floor setup, leveling applies only after Done.

Enable **Show pose axes** in Settings and apply the change to draw a tag-centered pose gizmo: red **X**, green **Y**, blue **Z**. The axes use the solved tag-to-camera pose and the same frame's camera intrinsics, then the same image-to-screen transform as the tag corners. Each axis is half a tag width long. These are tag-local axes, not gravity or field axes; a direction pointing toward/away from the camera can appear foreshortened. The option defaults off and is saved on the phone.

**Height units:** tag-center and manual floor heights show centimeters, with feet/inches in parentheses by default (for example `142.0 cm (4 ft 7.9 in)`). Disable **Settings → Show English units** for centimeters only. The preference is saved on the phone; it changes presentation, not stored meter values or tag-size calibration.

**Kalman filter:** tap the **Kalman on/off** checkbox in the control dock to compare live tag-card heights and the separate LiDAR/Tag camera ranges with filtering enabled or disabled. The control shows the selected sample count and applies each change immediately without opening Settings. It waits for the saved native state before accepting another tap. The checkbox in Settings controls the same saved preference. **Settings → Smoothing strength** offers 3, 5, 10, 20 or 30 equivalent samples, with 5 selected by default. More samples reduce jitter and add response lag. The setting is saved even while filtering is off. Kalman uses a recursive estimate rather than a fixed sample buffer; the sample count controls its noise ratio, with elapsed time accounted for between observations. It starts with the first current reading and resets when a tag disappears, a signal becomes unavailable, its height source changes, tracking/floor/settings change, or results expire. Duplicate IDs in one frame stay raw to avoid combining different tags.

Filtered cards show **Distance · Kalman**, and the selected panel marks a filtered height with **Kalman**. The displayed LiDAR Δ uses the displayed ranges. Detailed pose/depth diagnostics, quality gates, world-space height vectors, manual measurements, status payloads, recordings and playback retain the raw values. Smoothing improves readability; it does not establish measurement accuracy.

**View zoom:** pinch anywhere on the live image or use **1× / 2× / 4×**. Magnification is centered and limited to 1×–4×. The camera and depth previews zoom together; tag corners and axes use the matching screen transform, and measurement taps map back into the original image coordinates. The readout and controls remain their normal size. This changes the display only: it does not select another lens, add image detail, or change recorded sensor samples and solved poses.

Open **Settings** to edit:

| Setting | Initial value |
| --- | --- |
| Physical tag width | 165.1 mm / 6.5 inches |
| Maximum range | 5 m |
| Maximum plane incidence angle | 60° |
| Distance delta display threshold | 15 cm |
| Level floor with gravity | Off |
| Kalman filter | Off |
| Smoothing strength | 5 equivalent samples |
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
- **Pose Z** is forward camera-plane depth. **Distance** (range) is the Euclidean length of the translation vector. They differ for a tag away from the image center.
- **LiDAR center** is the matching-frame scene-depth sample at the detected tag center. The separate small-neighborhood mean includes only finite, positive, accepted-confidence samples; it does not silently replace a missing center sample.
- **Depth difference** is `abs(LiDAR center − pose Z)`. Green is at/below the warning threshold, amber is above warning through rejection, and red is above rejection. Missing or unusable data is neutral, not green.
- **Plane angle** is the angle between the tag-plane normal and the line of sight: 0° is head-on, 90° is edge-on. It drives the angle gate. **Center bearing** is the angle of the translation vector away from the optical axis and is shown separately.
- **Reprojection RMS** is calculated in image pixels from the four projected tag corners. The upstream solver's object-space error is a different quantity and is retained separately.
- **Decision margin** and corrected-bit count are raw decoder diagnostics, not a confidence percentage. A near-equal, distinct second pose is marked ambiguous. Missing pose/depth, low confidence, limited tracking, excessive range/angle, poor fit and mismatch get explicit reasons.

## Timing and records

The camera is configured for 30 Hz. Detection and pose estimation use one worker with one frame in flight; a busy worker drops incoming work instead of queuing old frames. The prior fixed 8 Hz analysis throttle is removed. The native overlay/panel uses current results directly; React Native receives only bounded status updates and manages settings. Actual analysis rate, latency and result age are shown rather than assuming that the device always achieves 30 analyses per second.

Each analyzed frame's event retains the calibration, tag width/settings, optical pose, quality diagnostics and synchronized depth samples. Changing settings invalidates results computed under the old settings. Accepted AR width estimates retain the endpoint and frame provenance. Original RGB, numeric depth/confidence and AR camera metadata continue to be recorded for later review.

The iPhone test should include a centered tag, an off-axis tag, a steeply angled tag, increasing distance, unavailable/low-confidence depth, and both sides of the mismatch thresholds. It should also check sustained actual analysis rate, stale-value clearing, size changes, repeated tag appearance/disappearance and export readability. These checks do not replace the later independent accuracy evaluation.
