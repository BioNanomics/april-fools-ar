# Milestone 0 capture format

Schema version 1 describes the on-device capture data. Preserve the complete exported MP4 so later analysis has the original inputs. It is not a calibrated field map. [MP4 recording format version 1](../recording-format/FORMAT.md) packages these files with readable YAML metadata; it is separate from the capture schema version.

## Explicit camera-relative pose readout (convention version 1)

`debugSettings.poseConvention` selects `rawOptical`, `ftcSdk`, or `frcPhotonVision` (the default). This is a presentation convention, independent of `tagSizeMode`, competition year, Auto size inference and the selected field package. It does not assert robot mounting extrinsics or a field-relative tag pose.

Each detection adds `poseReadout`, also copied into `debug.poseReadout`, or explicit null when no valid pose can be converted. A version-1 record contains:

- `convention`: the exact selected key; `conventionVersion: 1`.
- `reference: tag-relative-to-camera`, `matrixOrder: row-major`, `units: {length: meter, angle: degree}`, and a required profile-specific `rotationConvention` interpretation string.
- `cameraFrame` and `tagFrame`: explicit basis identifiers listed below.
- `translationMeters`: three camera-coordinate components of the tag center.
- `rotationRowMajor`: nine values mapping the named tag-local basis into the named camera basis, `pCamera = R × pTag + t`.
- `rollPitchYawDegrees`: **always `[roll,pitch,yaw]`**, including FTC. Its UI displays Pitch / Roll / Yaw by explicitly reordering this array. Raw optical labels its decomposition Rot X / Rot Y / Rot Z.
- `cameraDistanceMeters`: full 3D Euclidean center distance, invariant under profile change.
- `eulerSingular`: whether the profile's Euler decomposition is singular; the matrix remains authoritative.
- FTC only: `planarRangeMeters = hypot(ftcX,ftcY)`, `horizontalBearingDegrees = atan2(-ftcX,ftcY)` converted to degrees, and `elevationDegrees = atan2(ftcZ,ftcY)` converted to degrees. Other profiles omit these FTC-specific fields.

The basis identifiers and semantics are:

| Convention | `cameraFrame` | `tagFrame` |
| --- | --- | --- |
| `rawOptical` | `camera-optical-x-right-y-down-z-forward` | `apriltag-tag-x-right-y-down-z-into-tag` |
| `ftcSdk` | `ftc-sdk-camera-x-right-y-forward-z-up` | `ftc-sdk-tag-x-right-y-into-tag-z-up` |
| `frcPhotonVision` | `frc-photonvision-camera-x-forward-y-left-z-up` | `photonvision-tag-x-out-y-printed-right-z-up` |

FTC uses SDK intrinsic-YXZ extraction from the complete optical matrix, with yaw = −first, pitch = second, roll = third and the SDK's branch/singularity choices. Its converted matrix factors as `Rz(yaw) Rx(pitch) Ry(roll)`. FRC / PhotonVision applies the tag-local `Ry(π)` correction before full EDN→NWU basis conversion, then WPILib extrinsic XYZ Euler extraction. Thus an upright head-on raw identity pose gives FTC zero angles and FRC pose yaw 180°. Camera axes follow captured sensor orientation, not display rotation or gravity. Exact transforms and pinned interoperability sources are in [decision 004](decisions/004-pose-conventions.md).

The original raw `pose` object and existing optical debug fields retain their numeric definitions. Explicit debug names now accompany compatibility aliases: `opticalTranslationMeters`, `opticalRotationRowMajor`, `opticalEulerZYXDegrees`, `cameraDistanceMeters`, `viewingIncidenceDegrees`, `opticalAxisOffsetDegrees`, `poseOpticalDepthMeters`, `sceneOpticalDepthMeters` and `absoluteOpticalDepthDifferenceMeters`. Legacy `centerBearingDegrees` remains an unsigned optical-axis offset, rather than acquiring FTC signed-bearing semantics. A profile change does not change raw solver inputs, quality checks, scene-depth values, world geometry or stored historical files.

Readers validate convention/version, exact frames, rotation convention, units and matrix/angle consistency before using a derived record. Old captures without `poseReadout` retain their raw optical contract; absence is not evidence that they used FTC or PhotonVision. Unsupported or invalid derived metadata must not silently be presented as a valid named SDK pose. Original observations, including their legacy numeric values and timestamps, remain available for analysis.

## App-derived gravity-relative tag orientation

New AprilTag detections include an additive `gravityOrientation` dictionary, also copied into `debug.gravityOrientation`. It combines the tag-to-optical-camera rotation and the same source frame's gravity-aligned camera-to-world rotation, including the ARKit/optical axis conversion. No separate Core Motion stream, floor selection or depth sample is an input to this gravity calculation. Auto size resolution can still require scene depth before the source pose is available. `frameId`, `segmentId`, `timestamp` and `frameAgeSeconds` identify the source observation; `source`, `method`, `coordinateFrame`, `angleConvention` and `estimate` retain interpretation.

The current UI calls these app-derived quantities **Lean** and **Upright**; their historical Tilt/Twist keys retain their original meaning and are separate from FTC/FRC pose Euler angles. New explicit names `planeLeanFromVerticalDegrees` and `uprightRotationClockwiseDegrees` accompany the numerically identical legacy aliases `tiltFromVerticalDegrees` and `twistDegrees`. Both naming sets are null when unavailable. When `available` is true, `tiltFromVerticalDegrees` is in [0,90], with zero indicating a vertical printed plane. `twistDegrees` is in [-180,180], positive clockwise when viewing the printed front, relative to gravity projected into that plane. A near-horizontal plane has `twistAvailable: false`, null `twistDegrees` and `twistReason: horizontalTagPlane`; its tilt remains available. The record also preserves `worldFromTagRotationRowMajor` (nine values), `normalWorld` (unit +tag Z, into the print) and `upWorld` (unit -tag Y, toward the printed top). These world axes establish gravity-relative orientation, not surveyed field heading.

Limited tracking, stale/future frame ages, missing/invalid/ambiguous poses and failed range/incidence/decode/reprojection gates set `available: false`, retain `reason`, and leave all angles and world geometry null. A valid zero remains numeric. Gravity angles remain raw when height/distance readout smoothing is enabled. Recorded playback displays the saved angles within their original frame/segment lifetime; older captures without this dictionary show unavailable angles rather than a synthesized orientation. Existing `floorHeight` retains its independent confirmed-floor reference and depth/pose source.

## Files and clocks

Each session has a UUID directory containing `manifest.json`, `frames.jsonl`, `events.jsonl`, `rgb.mp4`, `frames/`, and `depth/`. JSONL contains one JSON object per line. UTF-8 text, meters, and seconds are used unless a field says otherwise.

`ARFrame.timestamp` is a monotonic time in seconds since system boot. It is not Unix time. `createdAt` and event `wallTime` are ISO-8601 wall-clock annotations. Video presentation timestamps are relative to `firstARFrameTimestamp`; a frame's `videoPTSSeconds` supplies that correspondence. Only entries with `videoAppended: true` were accepted by the video writer. Do not assume consecutive metadata entries correspond to consecutive video frames.

`frameId` identifies the source camera frame within the app process. `segmentId` identifies the current AR coordinate segment; interruption/reset boundaries invalidate previously selected endpoints. Do not compare world points from different segments as if their world frames were identical.

## RGB and geometry

RGB video uses H.264, targeting 30 fps, with no audio or burned-in overlays. It retains the clean camera feed for later processing. New manifests declare this in `videoContent` (`source: ARFrame.capturedImage`, `overlaysBurnedIn: false`, `audioRecorded: false`). A standard external player shows the clean camera video; live graphics are not part of the movie pixels. The app's native review player draws recorded geometry over this video with an optional **Recorded overlays** toggle. This is a playback visualization of saved evidence, not pixel-identical reconstruction of every historical screen. Selected frames are JPEGs at a target of 5 Hz and at positive-detection/measurement/bookmark events, subject to the bounded writer queue. A frame already saved as a JPEG is reused rather than duplicated. The preserved sensor image is not rotated to match the phone screen. `imageWidth`, `imageHeight`, `interfaceOrientation`, `viewportWidth`, `viewportHeight`, and `displayTransform` describe presentation.

`displayTransform` stores `[a, b, c, d, tx, ty]` for ARKit's affine mapping from normalized captured-image coordinates to normalized viewport coordinates. Invert it to map a screen tap to a normalized image coordinate. `intrinsicsColumnMajor` stores the 3×3 camera intrinsics in column-major order for the captured-image dimensions. `cameraToWorldColumnMajor` stores a 4×4 column-major transform.

The world is ARKit's right-handed, gravity-aligned frame with +Y up. The camera looks along −Z; +X is right and +Y is up. An image coordinate `(u, v)` with positive camera-plane depth `z` unprojects to:

```text
camera = [(u - cx) * z / fx, -(v - cy) * z / fy, -z, 1]
world  = cameraToWorld * camera
```

These are estimated AR coordinates, not a surveyed field origin. Plane observations and up to 200 feature points are sampled at approximately 1 Hz when available. The full ARKit world map and raw LiDAR hardware returns are not recorded.

## Numeric depth and confidence

The source is ARKit `sceneDepth`, without the optional `smoothedSceneDepth` stream. This is processed camera/LiDAR evidence, not raw hardware returns. Apple defines its values as distances from the [camera plane](https://developer.apple.com/documentation/arkit/ardepthdata), separate from 3D Euclidean camera distance. Each `.f32` file is row-major, tightly packed, little-endian Float32 camera-plane depth in meters, with dimensions from that record's `depthWidth` and `depthHeight`. Source padding is removed. NaN, non-finite, zero, or otherwise invalid samples must be rejected by consumers.

The depth and RGB images describe the same AR frame at different resolutions. Map via normalized image coordinates, or scale the image intrinsics to the depth grid. `depthPath`, `confidencePath`, `rgbImagePath`, `frameId`, and `timestamp` tie the samples together. Do not use a depth pixel index directly as a full-resolution RGB pixel index.

A `.confidence.u8` file is a matching packed grid of UInt8 categories: 0 low, 1 medium, 2 high. These categories are not metric error bars. A missing confidence map is not fabricated. For the MVP probe, invalid depth and low-confidence samples are rejected.

## Events and integrity

New recordings snapshot the installed app's build identity at session creation. `manifest.json.application` and the `recordingStarted` event's `application` contain the same `bundleId`, semantic `version`, `build` number, full Git `buildCommit`, ISO-8601 `buildDateUTC`, and boolean `workingTreeDirty`. The build date identifies the compiled package; the session's `createdAt`/event `wallTime` identifies when recording began. Exporting a recording after an app update preserves its original identity. Older recordings may lack the build date or full hash and are not rewritten with inferred values. Use `scripts/inspect-session.py --require-build-info <session>` to require the new fields.

AprilTag analysis uses the `tag36h11` family and the shared native AprilTag 3 detector. Each `aprilTagDetections` event identifies its source frame, coordinate segment, timestamp, image dimensions, intrinsics, camera pose and display transform. `detections` contains ID, family, Hamming corrections, decision margin, image-pixel center and four ordered image-pixel corners. An empty array with `analysisSucceeded: true` means the detector analyzed that frame and found no tags; it is distinct from a frame that was not analyzed or a failed analysis. Failures have `analysisSucceeded: false` and `detectorError`. The bounded worker now attempts every available camera frame (30 Hz configuration), drops work when busy and records latency; the older 8 Hz throttle applied to builds 2–3. Live outlines and readouts clear when stale. A detected ID or a passing diagnostic flag does not certify field placement.

Calibrated detections include the legacy raw optical `pose` when a valid solution exists. The actual solver uses homography initialization plus up to two orthogonal-iteration candidates; it does not call OpenCV `solvePnP`. Its `translation` is optical-camera `[x right, y down, z forward]` in meters. `rotationRowMajor` maps tag-local vectors into that optical camera frame. `eulerDegrees` is `[roll, pitch, yaw]` with `R = Rz(yaw) Ry(pitch) Rx(roll)`; the matrix remains authoritative at a singularity. `rangeMeters` is full 3D camera distance; `opticalAxisAngleDegrees` is unsigned optical-axis offset, not FTC signed bearing; `planeAngleDegrees` is acute viewing incidence. `reprojectionRMSEPixels` is the four-corner pixel RMS, distinct from upstream `poseError` in squared meters. Second-candidate fields are omitted when unavailable. A near-equal distinct solution is explicitly marked `ambiguous`.

Tag-size selection adds `debugSettings.tagSizeMode` (`auto`, `ftc`, `frc`, or `custom`), integer `competitionYear`, and a per-detection `tagSizeResolution` dictionary. New settings use Auto with year 0. FTC years name the season's ending year: 2024 CENTERSTAGE, 2025 INTO THE DEEP, 2026 DECODE and 2027 BIOBUZZ. FRC supports calendar years 2024–2026. Selecting FTC without a year defaults to 2027; FRC defaults to 2026. Custom retains the entered or accepted AR edge width and uses year 0. The field/year pair is validated and persisted.

Explicit field/year selections supply the nominal width without LiDAR inference. FTC 2024 CENTERSTAGE uses 0.0508 m for IDs 1–6, 8 and 9 and 0.127 m for IDs 7 and 10; an unknown ID retains its decoded outline without a scaled pose. FTC 2025 uses 0.1016 m, FTC 2026 uses 0.1651 m, FTC 2027 uses 0.08255 m, and FRC 2024–2026 use 0.1651 m. Single-size seasons apply their width under the operator's explicit selection, including for a practice print with another ID. These records describe the selected context rather than independently proven competition identity. FRC 2023 uses an unsupported tag family and is not an available preset.

Auto estimates width using the same frame's high-confidence center LiDAR depth (confidence category 2), normal tracking and a reliable, unambiguous reference pose passing the angle, reprojection and decoder gates. Supported widths are 0.0508, 0.08255, 0.1016, 0.127, 0.1524 and 0.1651 m. A unique match must be within 10%, tightened to 3% for the nearby 0.1524/0.1651 m sizes. Missing or ambiguous resolution retains the decoded detection without a scaled pose. Auto leaves competition identity and year unknown.

`tagSizeResolution.status` is `selected` or `unavailable`; `source`, `label` and `reason` retain selection/rejection context. `tagSizeMeters` is the selected width or null; `estimatedEdgeMeters` retains the automatic estimate when one could be computed. `fieldType` records the selected mode, and `competitionYear` records an explicit field year or null for Auto/custom. The automatic source is `sceneDepth-standard-match`; explicit modes retain their setting's source. Automatic records also retain the center depth/confidence, reference width and accepted relative tolerance. The applied `pose.tagSizeMeters` and `pose.tagSizeSource` are authoritative for that detection: `debugSettings.tagSizeMeters` is only a reference scale in Auto and mixed-size seasons, and tags within one frame can have different applied widths. Consumers must not substitute the reference width for a missing resolved width. Upgrading legacy saved settings without a mode changes the untouched `frc-default` width to Auto while preserving manual/AR overrides as custom; historical capture records are not rewritten.

Competition identity is not encoded by the shared `tag36h11` family or its ID. In particular, FRC and FTC DECODE both use a 0.1651 m black-border width; a matching size does not distinguish them. Auto uses LiDAR to choose scale, so subsequent pose-versus-LiDAR agreement is not an independent validation of tag size. [Tag-size references and limits](tag-debug-screen.md) list the official widths and supported seasons. Historical recordings preserve their original explicit size and do not acquire inferred competition labels, years or automatic-resolution evidence.

This pose convention differs from the ARKit camera transform above. To combine them, use `T_world_tag = T_world_ARcamera × diag(1,-1,-1,1) × T_optical_tag` with the documented matrix storage orders. Do not directly multiply the optical pose into the ARKit transform without that conversion.

Each detection's `depth` and `debug` dictionaries retain matching-frame center depth/confidence, filtered 3×3 mean and sample counts, the absolute difference `abs(centerDepthMeters - opticalPoseZMeters)`, quality/validity reasons, and the configured tag width/threshold context. A missing or rejected center is never replaced silently by its neighborhood mean and never receives a green depth-agreement result. The debug settings and accepted AR width-measurement provenance are retained with capture events; see [debug-screen conventions](tag-debug-screen.md).

Version 0.2.1 adds `floorHeight` to individual detections and their debug data. It describes a live tag-center height above the operator-confirmed floor, using the detection's source camera frame. An accepted center scene-depth sample is preferred; a valid tag pose supplies an explicitly labeled fallback when depth is unavailable. Pose-based height depends on the configured tag dimensions. Each result identifies availability, source and rejection reason, with compact source-frame and floor-plane provenance. Unavailable height is represented separately from numeric zero. These results are recorded with tag detections and do not add entries to the manual measurement history.

Version 0.3.0 adds per-detection `cameraRanges` to distinguish Euclidean distance to the camera from optical-axis depth. Accepted center scene depth is unprojected through the same frame's intrinsics; the norm of that optical point gives LiDAR range. Tag range is the norm of the solved optical translation. Raw optical Z values remain separate. These diagnostics do not require a floor reference, and unavailable inputs remain null rather than zero. Range availability only means the numeric diagnostic can be computed; the existing tag-quality status still determines whether a detection is usable.

Version 0.3.2 adds `cameraRanges.distanceDeltaMeters`, the full-precision absolute difference between valid LiDAR and tag Euclidean distances, or null when either is unavailable. The saved `debugSettings.distanceDeltaThresholdMeters` (default 0.15 m) controls whether **Δ 3D** (formerly **LiDAR Δ**) is displayed; it does not modify the recorded difference or the separate optical-Z quality thresholds. Live height vectors reuse `floorHeight.floorFootWorldMeters` and `floorHeight.worldMeters` from the source detection and do not add manual measurement events. Their label is projected from the world-space midpoint; the height remains gravity-vertical.

Floor references also distinguish observed slope from the effective measurement plane. `observedNormalWorld`, `observedTiltDegrees`, `tiltSource` and `floorFit` retain the LiDAR fit and its source/quality evidence. An unavailable fit has a null observed tilt; ARKit's gravity-aligned horizontal anchor is not treated as a measured zero slope. The saved `debugSettings.levelFloorWithGravity` defaults to false. When enabled, `normalWorld` and boundary vertices describe a horizontal plane through the selected floor center, while the original observed normal/tilt remain available. Leveling changes are recorded separately; existing measurement records keep their original floor snapshots.

`debugSettings.showImperialHeight` is a saved display preference, defaulting to `true` when absent in older settings. It controls the parenthesized feet/inches alongside centimeter heights. All numeric measurement, pose and `floorHeight.meters` records remain in meters; unit formatting never rewrites geometry or calibration.

`debugSettings.showPoseAxes` is an optional display preference (default `false` when absent in older settings). It controls the projected tag-local RGB axis gizmo; it does not change the pose solution, tag size or raw recorded geometry.

View-zoom builds add `displayZoom` and `previewDisplayTransform` to frame and AprilTag-analysis metadata. `displayTransform` retains the original sensor-to-unzoomed-viewport mapping. `previewDisplayTransform` applies the centered display magnification after that mapping; it does not describe a different camera calibration. A measurement point's `viewNormalized` stays in the unzoomed viewport coordinates used to sample the image/depth, and its `displayZoom` records the factor used by that tap. Raw images, depth, intrinsics and solved poses retain their original conventions.

`events.jsonl` includes bookmarks, selected measurement endpoints, tracking changes, segment boundaries, and session lifecycle events. An endpoint records its image/depth pixel, camera-frame identity, world point, confidence and depth source. With two valid endpoints in one segment, the app reports 3D Euclidean distance and signed `second.y - first.y` vertical difference separately. The vertical difference is not automatically floor-to-tag height.

Version 0.2.0 adds explicit floor selection and persistent spatial measurements. A floor selection retains the estimated plane boundary, world-space origin/normal, source frame/segment, and operator confirmation. A floor-height measurement intersects the vertical line through the tapped target with this confirmed plane. It records the floor intersection and target point separately, along with the floor snapshot used. It is a gravity-aligned height; a tilted floor's perpendicular distance is a different quantity. The app does not infer tag identity from a height tap.

Version 0.3.1 separates floor scanning from confirmation. A live selected candidate is not the measurement datum until the operator presses Done with enough coverage and current normal tracking. Manual distance, floor-height and tag-width probes are blocked until a floor is confirmed; the final floor snapshot is retained in `floorConfirmed` and subsequent measurement records. Re-entering Measure can reuse a confirmed floor in the same AR coordinate segment.

Completed measurements are immutable: later plane refinement or another selected floor does not rewrite their original endpoints or numeric values. `measurementsAtStart` events include existing live geometry so measurements taken before Start are also retained in the resulting recording. This snapshot contains their geometry/provenance, including source-point camera pose, intrinsics, image/depth dimensions, display transforms and sampled depth/confidence; it does not retroactively capture RGB or depth buffers from before recording began. `floorConfirmed`, `measurementCompleted`, `measurementsCleared`, and `measurementsInvalidated` events record floor selection, measurement creation, clearing and coordinate-segment invalidation. Follow event order when reconstructing what was visible, and retain invalidated measurements as historical evidence rather than placing them in a new segment.

Distance overlays derive a gravity-aligned right triangle from each saved `kind: distance` record's endpoints. Its corner is `(end.x, start.y, end.z)`: start-to-corner is horizontal, corner-to-end is vertical, and start-to-end is the direct hypotenuse. D/H/V labels use the shared geometry core; V retains the sign of `end.y - start.y`. These drawing aids do not introduce a new measured point or change recorded geometry. Playback can derive them for older captures as well. Each edge is clipped independently, and degenerate zero-length legs are omitted while their zero values remain visible in the distance summary.

The live overlay is projected from world coordinates through the current AR camera, intrinsics, display transform and view zoom. Brief limited tracking hides it and prevents new taps without erasing completed measurements in the same segment. Coordinate resets, interruptions, backgrounding and native-view detachment invalidate live placement. The exported data remains available for offline review; this release does not save/relocalize an AR world map or restore 3D placement after app restart. Both measurement endpoints require usable, finite scene depth and medium/high confidence for direct depth taps; the computed floor intersection is explicitly derived from the selected plane, not presented as another measured depth sample.

## On-device overlay playback

The review player reads the retained `manifest.json`, `frames.jsonl` and `events.jsonl`, verifying the log files against the original manifest's inventory. It uses accepted video frames (`videoAppended: true`) and their `videoPTSSeconds` for the displayed camera pose. Source-clock event timestamps are offset by `firstARFrameTimestamp`. Seeking reconstructs the applicable state so later measurements do not remain visible when scrubbing backward. Clearing, tracking loss and coordinate-segment changes retain their recorded semantics.

The playback canvas maps source sensor pixels through the MP4's actual video-track transform and aspect-fit video rectangle. It does not apply the original screen's crop or preview zoom again. Recorded world-space measurements, confirmed floors and tag-height endpoints are projected through the displayed frame's calibration. Tag corners use their original source frame; a short hold into another frame requires a usable recorded pose for reprojection, and stale results are hidden. The player does not run a new detector or invent missing sensor samples.

New frames include optional `previewMode` (`camera`, `depth`, or `confidence`). `previewModeAtStart` and `previewModeChanged` events also record the effective mode, AR timestamp, segment and frame identity. Recorded playback follows the displayed accepted frame's mode. Older captures lack this history, so their original view-switch sequence cannot be reconstructed; explicit Camera, Depth and Confidence playback choices can still inspect their saved maps.

Sensor playback indexes saved depth/confidence descriptors across frame and event rows, including `videoAppended: false` rows. Reused paths can omit dimensions, so compatible records for the same segment/frame are merged. A sample is held for at most 0.4 seconds within its original segment; it is not reprojected into a newer camera pose. Lazy background loading verifies path containment, dimensions, byte length and inventory SHA-256 before rendering. The sensor raster follows the actual movie transform and full video rectangle. Missing or invalid samples produce an explanation rather than invented data.

Measurement modes, floor visibility switches and panel expansion were not all recorded. Playback shows the available recorded geometry with its own visibility toggle. Overlay presentation does not modify the MP4 or its numeric data. Missing or invalid overlay metadata produces an unavailable message while clean video remains playable.

The writer retains at most three frames for disk work. Busy queues can omit frames or event snapshots; omissions are reported rather than assigned invented data. Capture counters distinguish accepted metadata, video, depth samples, and writer/video drops. Sample rates are targets, not guarantees.

Only a fully written manifest has `finalized: true`. Its `fileInventory` gives each payload file's relative path, byte length, and SHA-256. The manifest excludes itself from the inventory. A failed or interrupted finalization remains unavailable for normal export. Check `errors` as well as `finalized`.

MP4 export streams the original video and sidecar files into one self-contained movie below 4 GiB. It adds session, frame and event YAML tracks and an uncompressed TAR data track with the original sidecar files. The original movie is recoverable byte-for-byte without duplicating its video in the export. The export adds temporary storage roughly equal to the session size plus readable metadata; the original stays on the phone. Start with short sessions, export them, and verify their contents before a longer field visit. Stock FFmpeg can dump each YAML track directly; see [extraction instructions](../recording-format/README.md). Older ZIP exports are still supported by the analysis inspector.

Validate an exported bundle or copied session directory with:

```sh
npm ci --prefix recording-format/npm
python3 scripts/inspect-session.py /path/to/recording.mp4
```

For the short device check with a known visible tag, add `--require-tags` to fail when the export contains no decoded tag.

This checks readability, numeric buffer sizes, sample decoding, and payload checksums. It does not establish measurement accuracy or replace the field review.


## Shared calculation provenance (additive schema-1 fields)

New session manifests and AprilTag events include `calculationCore`: library name/version, C ABI and algorithm-contract versions, internal units, matrix/axis convention, and the containing application commit/build date/dirty flag. This identifies the numerical implementation independently of the MP4 transport version and capture schema. Existing `application` metadata is retained.

Each AprilTag event also records the exact `floorSnapshot` selected for that source frame, or explicit null if no floor was selected. Each detection's `floorHeight.frameAgeSeconds` records the age used by the live eligibility check. A reader must respect an explicit null snapshot; only old records without the key may fall back to saved height provenance. Historical records without age cannot reproduce the complete stale-frame gate and must say so.

These fields travel unchanged through the existing MP4 YAML tracks and original-sidecar extraction. Replay uses original event order and capture timestamps; MP4 metadata packet timestamps are not sensor timestamps. `videoAppended:false` remains valid metadata and must not be discarded. See [shared-core replay](../native/SpatialCore/README.md).


## Saved playback and presentation orientation

On Stop & save, the recorder completes the raw session then automatically publishes a self-contained MP4 under the sibling `recordings/` directory. Source session folders remain recovery/analysis copies. A failed MP4 preparation does not delete or invalidate a completed source capture; Play/Share retry it. A zero-frame capture is never marked finalized.

New `videoContent` fields include `playbackTransform` (`[a,b,c,d,tx,ty]` in image-pixel coordinates), `orientationSource`, and `orientationLockedAtFirstFrame`. The movie uses the first frame's sensor-to-display rotation, without viewport cropping or display zoom. Raw images, intrinsics and all recorded display transforms retain their original conventions. A phone rotation during recording is visible as camera movement; it does not rewrite earlier frame coordinates or change the single movie-track orientation.

Play opens the saved video with native AVKit controls and recorded overlays enabled by default. The **Recorded overlays** toggle changes only the playback canvas; it does not alter the persistent MP4. Share uses that clean MP4 and is no longer a packaging step. Legacy sessions are prepared lazily, using their first frame to infer presentation rotation, while preserving byte-exact source restoration.
