# AprilTag debug screen

The debug screen compares two estimates from the same AR camera frame: the pose solved from the tag corners and applied physical tag width, and ARKit's scene-depth sample at the tag center. In Auto size mode, LiDAR also selects the tag width, so agreement is partly a consequence of that selection. It does not independently validate the tag dimensions or establish surveyed field accuracy.

## Tag pose profiles and gravity measurements

**Details → Tag pose (camera-relative)** names the active **Pose profile**. Settings offers **FRC / PhotonVision** (the default), **FTC SDK**, and **Raw optical**, independently of tag-size mode and field/year selections. Auto size never chooses a coordinate profile or identifies the competition.

- **FRC / PhotonVision:** camera X forward, Y left, Z up; Roll / Pitch / Yaw about X / Y / Z, with `R = Rz(yaw) Ry(pitch) Rx(roll)`. The tag basis has X out of the print, Y printed right, Z printed up. A head-on upright tag has pose yaw 180°.
- **FTC SDK:** camera X right, Y forward, Z up; Pitch / Roll / Yaw about X / Y / Z. The SDK's rotation convention is `R = Rz(yaw) Rx(pitch) Ry(roll)`, obtained from intrinsic YXZ extraction of the full raw matrix. A head-on upright tag has zero angles. FTC planar range is `hypot(X,Y)`, horizontal bearing is `atan2(-X,Y)` (positive left), and elevation is `atan2(Z,Y)` (positive up); elevation uses forward depth, not planar range.
- **Raw optical:** camera X right, Y down, Z forward; diagnostic Rot X / Rot Y / Rot Z use `R = Rz(Rot Z) Ry(Rot Y) Rx(Rot X)`. A head-on upright tag has identity rotation. The tag's local axes are X printed right, Y printed down, Z into the print.

All profile axes refer to the captured camera sensor orientation, before screen rotation/cropping. They describe the tag relative to the camera, separate from the camera's own attitude, robot pose or field pose. Changing profile derives a different basis from the full pose matrix; it never just relabels the raw Euler values. The matrix is authoritative at Euler singularities. [The convention decision](decisions/004-pose-conventions.md) records exact transforms, versioned interoperability sources and examples.

Each tag card shows app-derived **Lean** and **Upright**, formerly Tilt and Twist. Lean is the unsigned printed-plane departure from vertical: 0° is vertical and 90° horizontal. Upright is clockwise-positive printed rotation from gravity-defined upright within that plane, viewed from the printed front. A horizontal plane has no gravity-defined upright direction, so Upright is unavailable. These measurements are separate from FTC/FRC pose pitch, roll and yaw, and from floor tilt.

Lean and Upright combine the detected tag rotation with the same captured frame's ARKit camera orientation. Turning the phone should approximately preserve them for a stationary tag. They require normal tracking and a current, resolved, unambiguous pose passing distance, viewing-incidence and decoder/reprojection checks. Neither a floor nor scene depth is an input to this gravity calculation; Auto size still needs usable scene depth to resolve the pose's scale. Missing values show **—**, distinct from zero. Height/distance smoothing leaves these angles unsmoothed, and changing pose profile leaves their definitions unchanged. Gravity supplies no absolute field heading.

Tag-center height uses the same source-frame camera transform and the confirmed floor, preferring accepted scene depth with an explicit tag-pose fallback when depth is unavailable. Changing the floor changes that height reference, independently of Lean and Upright.

## Using it

**Tags** is the default live view. The camera fills the screen behind a compact control dock. In portrait, all primary controls occupy its lower half: **Tags / Measure / Saved / Details / More**, then **Kalman / zoom / Settings**, then **Name / Record / Bookmark**. Small live cards show every detected tag's floor height and an aligned **Distance** comparison for **LiDAR** and **Tag**. These are straight-line camera-to-tag-center distances, including horizontal/vertical offset. **LiDAR Δ** appears only when their absolute difference exceeds **Settings → Distance delta threshold (cm)** (15 cm by default). Missing estimates do not produce a delta. Tap a detected tag or open **Details** in the dock for the selected camera-relative tag pose, raw Pose Z / Scene Z, their difference, 3D distance, viewing incidence, optical-axis offset and decoder quality in a scrollable tool panel. Opening tools does not crop, resize or change the camera's projection.

Tag outlines, four corner points and IDs remain on the camera image. Tap a tag to select it and open its details panel; otherwise the view chooses a tag near the image center without opening a panel. Tapping the same tag again reopens details after closing it. The upper readouts are passive. **Measure** opens floor selection and manual distance/height tools in a lower-half scroll panel, with recording controls pinned below it. **Done** closes a tool panel; tap **Measure** again to reopen its controls. **More** stays a lower-half panel and contains About & sponsors and version/release notes. About and Sponsors share one full-screen page with About, Privacy, Licenses and Done navigation along the bottom. The version badge stays visible in the upper right and is tappable; it and More open the same full-screen Version page, with Version, Release notes and Done along the bottom. In landscape, capture controls and tools move to a right-side panel below the version badge, clear of the camera cutout and home indicator. Navigation wraps into a compact grid, Kalman and Settings share a row, zoom has its own row, and Record stays pinned below the scrollable tools. Measurement, Details, More, Name and Saved use the same side panel; Settings also opens on the right with pinned Cancel/Apply actions. In portrait, these panels remain in the lower half. Rotating retains the camera, current recording, floor/tool selection, zoom and settings draft.

**Two-point distance:** after placing the second surface point, the yellow **D** line shows the direct 3D distance. Dashed cyan **H** and orange **V** lines show the horizontal and vertical legs of its right triangle. H includes displacement in both horizontal world directions and stays level with gravity as the phone moves. V is positive when the second point is higher and negative when it is lower. All three distance values use meters. For example, H = 3 m and V = 4 m give D = 5 m. Equal-height or vertically aligned points show their zero component in the distance label without redundant overlapping legs. The triangle appears in recorded playback too, using the saved endpoints. Floor-height and tag-width probes keep their existing behavior.

In **Details**, the underlined labels are links: tap **Lean**, **Upright**, **Pose Z**, **Scene Z**, **|Δ Z|**, **Axis offset**, **Incidence**, the active pose profile, or any other metric label to open its definition in the [measurement glossary](tag-metric-glossary.md). The glossary includes diagrams and is bundled with the app for offline use. **Contents** lets you browse terms, **Back** returns to the previous definition, and **Done** returns to the expanded readout. Definitions are maintained in `docs/tag-metric-glossary.md` and `docs/diagrams/`; the iOS build generates the bundled page from those sources.

**Automatic floor height:** enter Measure and scan the floor. A classified floor can be highlighted automatically; tap the correct floor if needed. Press **Done** when coverage and tracking are ready, then return to Tag debug. Every usable detected tag shows its estimated center height beside its ID without a per-tag tap. The selected-tag readout identifies **LiDAR** or **Pose** as the source. LiDAR uses the accepted depth at the detected center; the pose fallback depends on the resolved physical width for that detection. Height is vertical above the confirmed floor plane, including when that plane is slightly sloped. These are estimates, not independently verified physical dimensions. Missing/invalid input displays an unavailable height, and resetting the AR coordinate segment requires selecting the floor again. Automatic tag heights do not create persistent manual measurement vectors.

Each usable tag also gets a live world-space height vector from its floor intersection to the tag center, with the height label halfway along the vector. It remains vertical with gravity, even if the detected floor is slightly tilted. These live vectors reproject as the camera moves and clear when their source detection expires, tracking is lost or the floor changes. Existing manually saved measurements retain their separate persistence.

A small dotted 30 cm square marks each height vector's floor foot. It follows the active measurement floor: green for level (within 0.5°), yellow for tilted, and neutral gray when tilt is unavailable. Gravity leveling makes the reference horizontal and green. Saved manual height vectors keep the floor reference used when they were measured.

The camera view shows the **detected floor tilt** in degrees from horizontal. The estimate comes from a robust fit to usable LiDAR samples across the selected floor; insufficient coverage or inconsistent depth shows **tilt unavailable**. ARKit's horizontal plane anchors are already constrained to be level, so their rotation alone cannot establish physical floor tilt. **Settings → Level floor with gravity** is off by default. Turning it on uses a horizontal measurement plane at the selected floor's center elevation; the original tilt remains visible. Turning it off restores the detected floor plane. Apply the setting to change the current reference and save the preference. Completed manual measurements keep their original floor and values. During floor setup, leveling applies only after Done.

Enable **Show pose axes** in Settings and apply the change to draw a tag-centered pose gizmo: red **X**, green **Y**, blue **Z**. The axes use the solved tag-to-camera pose and the same frame's camera intrinsics, then the same image-to-screen transform as the tag corners. Each axis is half a tag width long. These retain the raw tag-local X printed right / Y printed down / Z into-print basis, independently of the selected pose readout profile; a direction pointing toward/away from the camera can appear foreshortened. The option defaults off and is saved on the phone.

**Height units:** tag-center and manual floor heights show centimeters, with feet/inches in parentheses by default (for example `142.0 cm (4 ft 7.9 in)`). Disable **Settings → Show English units** for centimeters only. The preference is saved on the phone; it changes presentation, not stored meter values or tag-size calibration.

**Kalman filter:** tap the **Kalman on/off** checkbox in the control dock to compare live tag-card heights and the separate LiDAR/Tag camera ranges with filtering enabled or disabled. The control shows the selected sample count and applies each change immediately without opening Settings. It waits for the saved native state before accepting another tap. The checkbox in Settings controls the same saved preference. **Settings → Smoothing strength** offers 3, 5, 10, 20 or 30 equivalent samples, with 5 selected by default. More samples reduce jitter and add response lag. The setting is saved even while filtering is off. Kalman uses a recursive estimate rather than a fixed sample buffer; the sample count controls its noise ratio, with elapsed time accounted for between observations. It starts with the first current reading and resets when a tag disappears, a signal becomes unavailable, its height source changes, tracking/floor/settings change, or results expire. Duplicate IDs in one frame stay raw to avoid combining different tags.

Filtered cards show **Distance · Kalman**, and the selected panel marks a filtered height with **Kalman**. The displayed LiDAR Δ uses the displayed ranges. Detailed pose/depth diagnostics, quality gates, world-space height vectors, manual measurements, status payloads, recordings and playback retain the raw values. Smoothing improves readability; it does not establish measurement accuracy.

**View zoom:** pinch anywhere on the live image or use **1× / 2× / 4×**. Magnification is centered and limited to 1×–4×. The camera and depth previews zoom together; tag corners and axes use the matching screen transform, and measurement taps map back into the original image coordinates. The readout and controls remain their normal size. This changes the display only: it does not select another lens, add image detail, or change recorded sensor samples and solved poses.

Open **Settings** to edit:

| Setting | Initial value |
| --- | --- |
| Pose profile | FRC / PhotonVision; FTC SDK or Raw optical also available |
| Field type | Auto (LiDAR) for new settings; FTC, FRC, or Custom width |
| FTC competition year | Defaults to 2026–27 BIOBUZZ when FTC is selected |
| FRC competition year | Defaults to 2026 REBUILT when FRC is selected |
| Maximum 3D distance (m) | 5 m |
| Maximum viewing incidence (°) | 60° |
| Distance delta display threshold | 15 cm |
| Level floor with gravity | Off |
| Kalman filter | Off |
| Smoothing strength | 5 equivalent samples |
| Depth mismatch warning | 10 cm |
| Depth mismatch rejection | 15 cm |
| Maximum corner reprojection RMS | 3 pixels |

Tag width is the distance between the detection corners at the black/white border, not the outside of the paper. This is the size definition used by [the upstream pose estimator](https://github.com/AprilRobotics/apriltag#pose-estimation). FTC sizes vary by season:

| Physical black-border width | Official use |
| --- | --- |
| 50.8 mm / 2 inches | [FTC CENTERSTAGE small tags](https://firstinspires.blob.core.windows.net/ftc/2023-24/apriltag-us-letter.pdf) |
| 82.55 mm / 3.25 inches | [FTC BIOBUZZ individual tags, Figure 9-15](https://ftc-resources.firstinspires.org/ftc/game/manual-09) |
| 101.6 mm / 4 inches | [FTC INTO THE DEEP](https://ftc-resources.firstinspires.org/ftc/archive/2025/game/apriltag-us) |
| 127 mm / 5 inches | [FTC CENTERSTAGE large tags](https://firstinspires.blob.core.windows.net/ftc/2023-24/apriltag-us-letter.pdf) |
| 152.4 mm / 6 inches | [FTC sample tags 585/586](https://ftc-docs.firstinspires.org/en/latest/apriltag/vision_portal/apriltag_metadata/apriltag-metadata.html) |
| 165.1 mm / 6.5 inches | [FRC](https://docs.wpilib.org/en/stable/docs/software/vision-processing/apriltag/apriltag-intro.html) and [FTC DECODE](https://ftc-resources.firstinspires.org/ftc/archive/2026/field/apriltag-us) |

Field type controls physical size independently of **Pose profile**. Choose **FTC** or **FRC** under **Field type**, then select **Competition year** to use a known season without relying on LiDAR to choose size. FTC displays the full season span and stores its ending year; FRC stores the calendar year. These selections are saved on the device.

| Field and competition year | Applied black-border width |
| --- | --- |
| FTC 2023–24 CENTERSTAGE (stored as 2024) | 2 inches for IDs 1–6, 8 and 9; 5 inches for IDs 7 and 10 |
| FTC 2024–25 INTO THE DEEP (2025) | 4 inches |
| FTC 2025–26 DECODE (2026) | 6.5 inches |
| FTC 2026–27 BIOBUZZ (2027) | 3.25 inches |
| FRC 2024 CRESCENDO, 2025 REEFSCAPE, 2026 REBUILT | 6.5 inches |

CENTERSTAGE's backdrop tags are all 2 inches, as documented in the [official backdrop print](https://www.firstinspires.org/sites/default/files/uploads/resource_library/ftc/apriltags-backdrop.pdf); its audience-side size map comes from the [official audience print](https://firstinspires.blob.core.windows.net/ftc/2023-24/apriltag-us-letter.pdf). A CENTERSTAGE ID outside its known map leaves the pose unavailable and prompts for matching field/year settings or a custom width. Single-size seasons apply their nominal size under the operator's explicit field selection. This selection supplies context; it does not prove that a print belongs to that competition. FRC 2023 is not offered because its [official tags use the 16h5 family](https://firstfrc.blob.core.windows.net/frc2023/Manual/HTML/2023FRCGameManual.htm), while this detector supports tag36h11.

**Auto (LiDAR)** considers the six supported widths separately for each detection. It requires normal tracking, a usable unambiguous corner pose and the same frame's high-confidence center LiDAR depth (confidence category 2). It estimates physical width from the ratio between LiDAR depth and the reference pose's optical Z, then accepts a unique standard width within 10%; the nearby 6- and 6.5-inch sizes use a tighter 3% tolerance to avoid confusing sample prints with field tags. Without those inputs or a unique match, the ID and outline remain visible while the scaled pose is unavailable. Auto identifies a nominal physical width, and leaves competition year unknown. Select an explicit field/year or custom measured width when Auto cannot resolve it.

On upgrade, the former untouched FRC default becomes Auto; existing manual/AR widths become custom. Once saved, an explicit field/year is retained. Choose **Custom width** to enter a measured print size; accepting an AR edge measurement also selects Custom width.

FTC and FRC share the `tag36h11` family and overlapping IDs. An ID does not encode a physical size or competition, and 6.5-inch tags are shared by FRC and FTC DECODE. Auto identifies a supported physical width; it cannot establish competition identity from a shared size. A rescaled practice print may require a custom width.

You can type a measured width or choose **Measure tag width with AR**. For an AR estimate, tap two adjacent boundary corners on one physical tag edge. Review the resulting distance and press **Use width** to apply it. Cancel leaves the configured width unchanged. The estimate comes from the existing AR/LiDAR endpoint measurements, not from a pose already scaled by the configured width. It remains sensitive to tap placement, depth resolution and tracking error, so a carefully measured physical width is preferable when available.

## Coordinate and quality definitions

- The raw detector pose uses standard AprilTag optical coordinates: **+X right, +Y down, +Z forward**, in meters. Its matrix maps tag-local vectors into the optical camera frame: `pCamera = R × pTag + t`. ARKit camera +Y-up / −Z-forward is converted explicitly when composing world geometry.
- Profile XYZ and rotation values are camera-relative. A camera mounting transform is needed for robot-relative values, and a field layout plus an identified field frame is needed for field-relative values. The selected display profile does not supply those transforms.
- The actual pose solver initializes from homography and refines up to two candidates with **orthogonal iteration**, using the matching camera intrinsics and the detection's resolved physical width. **PnP** names the general pose problem; this app does not call OpenCV `solvePnP`. The model is zero-skew pinhole and accepts no separately measured lens-distortion coefficients.
- **Pose Z** always means forward optical pose depth, even in a profile where Z means up. **Scene Z** is ARKit scene-depth at the center pixel, measured from the camera plane. It is processed LiDAR/camera evidence, separate from raw LiDAR hardware returns.
- **3D dist** is the Euclidean camera-to-tag-center norm. **FTC planar range** instead excludes camera-relative vertical displacement. For raw `(3,−4,4)` m: 3D distance ≈ 6.403 m, FTC range = 5 m, bearing ≈ −36.87°, elevation = +45°.
- The separate confidence-filtered **3×3 mean** never substitutes for a missing center scene-depth sample. Confidence categories are not accuracy percentages.
- **|Δ Z|** is `abs(Scene Z − Pose Z)`, separate from the live card's difference between two 3D distances. Green is at/below warning, amber above warning through rejection, red above rejection; unavailable is neutral. Auto size uses the same depth to select scale, so agreement is not an independent size validation.
- **Incidence**, formerly Plane, is the acute angle between the tag-plane normal and the line of sight: 0° head-on, 90° edge-on. It drives the viewing-angle gate. **Axis offset**, formerly Bearing, is `atan2(hypot(rawX,rawY),rawZ)`: an unsigned full 3D offset from the optical axis, distinct from signed FTC horizontal bearing.
- **Reprojection RMS** is four-corner image-pixel error. The upstream solver's object-space squared-distance error is a different metric. Neither verifies physical tag size.
- **Decision margin** and Hamming corrected-bit count are raw decoder diagnostics, not confidence percentages. A near-equal distinct second pose is marked ambiguous. Missing pose/depth, low confidence, limited tracking, excessive distance/incidence, poor fit and mismatch retain explicit reasons.

Definitions and diagrams, including the old names as aliases, are in the offline [measurement glossary](tag-metric-glossary.md).

## Timing and records

The camera is configured for 30 Hz. Detection and pose estimation use one worker with one frame in flight; a busy worker drops incoming work instead of queuing old frames. The prior fixed 8 Hz analysis throttle is removed. The native overlay/panel uses current results directly; React Native receives only bounded status updates and manages settings. Actual analysis rate, latency and result age are shown rather than assuming that the device always achieves 30 analyses per second.

Each analyzed frame's event retains the calibration, field type, competition year, size settings, per-detection width resolution, unchanged raw optical pose, versioned profile-specific `poseReadout`, quality diagnostics and synchronized depth samples. The applied width belongs to each detection's pose; in Auto and mixed-size seasons the settings width is only the reference scale used before resolution. Changing settings invalidates results computed under the old settings. Accepted AR width estimates retain the endpoint and frame provenance. Original RGB, numeric depth/confidence and AR camera metadata continue to be recorded for later review.

The iPhone test should include known FTC and FRC widths in the same view, a centered tag, an off-axis tag, a steeply angled tag, increasing distance, unavailable/low-confidence depth, unsupported print sizes, and both sides of the mismatch thresholds with an explicit width. It should also check sustained actual analysis rate, stale-value clearing, size changes, repeated tag appearance/disappearance and export readability. Automatic size selection still requires physical-camera validation; these checks do not replace the later independent accuracy evaluation.
