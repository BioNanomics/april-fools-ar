# Milestone 0 capture format

Schema version 1 describes the on-device capture data. Preserve the complete exported MP4 so later analysis has the original inputs. It is not a calibrated field map. [MP4 recording format version 1](../recording-format/FORMAT.md) packages these files with readable YAML metadata; it is separate from the capture schema version.

## Files and clocks

Each session has a UUID directory containing `manifest.json`, `frames.jsonl`, `events.jsonl`, `rgb.mp4`, `frames/`, and `depth/`. JSONL contains one JSON object per line. UTF-8 text, meters, and seconds are used unless a field says otherwise.

`ARFrame.timestamp` is a monotonic time in seconds since system boot. It is not Unix time. `createdAt` and event `wallTime` are ISO-8601 wall-clock annotations. Video presentation timestamps are relative to `firstARFrameTimestamp`; a frame's `videoPTSSeconds` supplies that correspondence. Only entries with `videoAppended: true` were accepted by the video writer. Do not assume consecutive metadata entries correspond to consecutive video frames.

`frameId` identifies the source camera frame within the app process. `segmentId` identifies the current AR coordinate segment; interruption/reset boundaries invalidate previously selected endpoints. Do not compare world points from different segments as if their world frames were identical.

## RGB and geometry

RGB video uses H.264, targeting 30 fps, with no audio or burned-in overlays. It retains the clean camera feed for later processing. New manifests declare this in `videoContent` (`source: ARFrame.capturedImage`, `overlaysBurnedIn: false`, `audioRecorded: false`). A standard player shows the clean camera video; live graphics are not part of the movie pixels. Detection, measurement, floor and display metadata can support a later overlay viewer, but the app does not yet replay those overlays offline or promise pixel-identical screen reconstruction. Selected frames are JPEGs at a target of 5 Hz and at positive-detection/measurement/bookmark events, subject to the bounded writer queue. A frame already saved as a JPEG is reused rather than duplicated. The preserved sensor image is not rotated to match the phone screen. `imageWidth`, `imageHeight`, `interfaceOrientation`, `viewportWidth`, `viewportHeight`, and `displayTransform` describe presentation.

`displayTransform` stores `[a, b, c, d, tx, ty]` for ARKit's affine mapping from normalized captured-image coordinates to normalized viewport coordinates. Invert it to map a screen tap to a normalized image coordinate. `intrinsicsColumnMajor` stores the 3×3 camera intrinsics in column-major order for the captured-image dimensions. `cameraToWorldColumnMajor` stores a 4×4 column-major transform.

The world is ARKit's right-handed, gravity-aligned frame with +Y up. The camera looks along −Z; +X is right and +Y is up. An image coordinate `(u, v)` with positive camera-plane depth `z` unprojects to:

```text
camera = [(u - cx) * z / fx, -(v - cy) * z / fy, -z, 1]
world  = cameraToWorld * camera
```

These are estimated AR coordinates, not a surveyed field origin. Plane observations and up to 200 feature points are sampled at approximately 1 Hz when available. The full ARKit world map and raw LiDAR hardware returns are not recorded.

## Numeric depth and confidence

The source is ARKit `sceneDepth`, without the optional `smoothedSceneDepth` stream. Each `.f32` file is row-major, tightly packed, little-endian Float32 camera-plane depth in meters, with dimensions from that record's `depthWidth` and `depthHeight`. Source padding is removed. NaN, non-finite, zero, or otherwise invalid samples must be rejected by consumers.

The depth and RGB images describe the same AR frame at different resolutions. Map via normalized image coordinates, or scale the image intrinsics to the depth grid. `depthPath`, `confidencePath`, `rgbImagePath`, `frameId`, and `timestamp` tie the samples together. Do not use a depth pixel index directly as a full-resolution RGB pixel index.

A `.confidence.u8` file is a matching packed grid of UInt8 categories: 0 low, 1 medium, 2 high. These categories are not metric error bars. A missing confidence map is not fabricated. For the MVP probe, invalid depth and low-confidence samples are rejected.

## Events and integrity

New recordings snapshot the installed app's build identity at session creation. `manifest.json.application` and the `recordingStarted` event's `application` contain the same `bundleId`, semantic `version`, `build` number, full Git `buildCommit`, ISO-8601 `buildDateUTC`, and boolean `workingTreeDirty`. The build date identifies the compiled package; the session's `createdAt`/event `wallTime` identifies when recording began. Exporting a recording after an app update preserves its original identity. Older recordings may lack the build date or full hash and are not rewritten with inferred values. Use `scripts/inspect-session.py --require-build-info <session>` to require the new fields.

AprilTag analysis uses the `tag36h11` family and the shared native AprilTag 3 detector. Each `aprilTagDetections` event identifies its source frame, coordinate segment, timestamp, image dimensions, intrinsics, camera pose and display transform. `detections` contains ID, family, Hamming corrections, decision margin, image-pixel center and four ordered image-pixel corners. An empty array with `analysisSucceeded: true` means the detector analyzed that frame and found no tags; it is distinct from a frame that was not analyzed or a failed analysis. Failures have `analysisSucceeded: false` and `detectorError`. The bounded worker now attempts every available camera frame (30 Hz configuration), drops work when busy and records latency; the older 8 Hz throttle applied to builds 2–3. Live outlines and readouts clear when stale. A detected ID or a passing diagnostic flag does not certify field placement.

Calibrated detections include `pose` when a valid solution exists. Its `translation` is optical-camera `[x right, y down, z forward]` in meters. `rotationRowMajor` maps tag-local vectors into that optical camera frame. `eulerDegrees` is `[roll, pitch, yaw]` with `R = Rz(yaw) Ry(pitch) Rx(roll)`; the matrix remains authoritative at a singularity. `rangeMeters` is Euclidean range; `opticalAxisAngleDegrees` is center bearing; `planeAngleDegrees` is normal-to-view incidence. `reprojectionRMSEPixels` is the four-corner pixel RMS, distinct from upstream `poseError` in squared meters. Second-candidate fields are omitted when unavailable. A near-equal distinct solution is explicitly marked `ambiguous`.

This pose convention differs from the ARKit camera transform above. To combine them, use `T_world_tag = T_world_ARcamera × diag(1,-1,-1,1) × T_optical_tag` with the documented matrix storage orders. Do not directly multiply the optical pose into the ARKit transform without that conversion.

Each detection's `depth` and `debug` dictionaries retain matching-frame center depth/confidence, filtered 3×3 mean and sample counts, the absolute difference `abs(centerDepthMeters - opticalPoseZMeters)`, quality/validity reasons, and the configured tag width/threshold context. A missing or rejected center is never replaced silently by its neighborhood mean and never receives a green depth-agreement result. The debug settings and accepted AR width-measurement provenance are retained with capture events; see [debug-screen conventions](tag-debug-screen.md).

Version 0.2.1 adds `floorHeight` to individual detections and their debug data. It describes a live tag-center height above the operator-confirmed floor, using the detection's source camera frame. An accepted center scene-depth sample is preferred; a valid tag pose supplies an explicitly labeled fallback when depth is unavailable. Pose-based height depends on the configured tag dimensions. Each result identifies availability, source and rejection reason, with compact source-frame and floor-plane provenance. Unavailable height is represented separately from numeric zero. These results are recorded with tag detections and do not add entries to the manual measurement history.

Version 0.3.0 adds per-detection `cameraRanges` to distinguish Euclidean distance to the camera from optical-axis depth. Accepted center scene depth is unprojected through the same frame's intrinsics; the norm of that optical point gives LiDAR range. Tag range is the norm of the solved optical translation. Raw optical Z values remain separate. These diagnostics do not require a floor reference, and unavailable inputs remain null rather than zero. Range availability only means the numeric diagnostic can be computed; the existing tag-quality status still determines whether a detection is usable.

Version 0.3.2 adds `cameraRanges.distanceDeltaMeters`, the full-precision absolute difference between valid LiDAR and tag Euclidean distances, or null when either is unavailable. The saved `debugSettings.distanceDeltaThresholdMeters` (default 0.15 m) controls whether **LiDAR Δ** is displayed; it does not modify the recorded difference or the separate optical-Z quality thresholds. Live height vectors reuse `floorHeight.floorFootWorldMeters` and `floorHeight.worldMeters` from the source detection and do not add manual measurement events. Their label is projected from the world-space midpoint; the height remains gravity-vertical.

Floor references also distinguish observed slope from the effective measurement plane. `observedNormalWorld`, `observedTiltDegrees`, `tiltSource` and `floorFit` retain the LiDAR fit and its source/quality evidence. An unavailable fit has a null observed tilt; ARKit's gravity-aligned horizontal anchor is not treated as a measured zero slope. The saved `debugSettings.levelFloorWithGravity` defaults to false. When enabled, `normalWorld` and boundary vertices describe a horizontal plane through the selected floor center, while the original observed normal/tilt remain available. Leveling changes are recorded separately; existing measurement records keep their original floor snapshots.

`debugSettings.showImperialHeight` is a saved display preference, defaulting to `true` when absent in older settings. It controls the parenthesized feet/inches alongside centimeter heights. All numeric measurement, pose and `floorHeight.meters` records remain in meters; unit formatting never rewrites geometry or calibration.

`debugSettings.showPoseAxes` is an optional display preference (default `false` when absent in older settings). It controls the projected tag-local RGB axis gizmo; it does not change the pose solution, tag size or raw recorded geometry.

View-zoom builds add `displayZoom` and `previewDisplayTransform` to frame and AprilTag-analysis metadata. `displayTransform` retains the original sensor-to-unzoomed-viewport mapping. `previewDisplayTransform` applies the centered display magnification after that mapping; it does not describe a different camera calibration. A measurement point's `viewNormalized` stays in the unzoomed viewport coordinates used to sample the image/depth, and its `displayZoom` records the factor used by that tap. Raw images, depth, intrinsics and solved poses retain their original conventions.

`events.jsonl` includes bookmarks, selected measurement endpoints, tracking changes, segment boundaries, and session lifecycle events. An endpoint records its image/depth pixel, camera-frame identity, world point, confidence and depth source. With two valid endpoints in one segment, the app reports 3D Euclidean distance and signed `second.y - first.y` vertical difference separately. The vertical difference is not automatically floor-to-tag height.

Version 0.2.0 adds explicit floor selection and persistent spatial measurements. A floor selection retains the estimated plane boundary, world-space origin/normal, source frame/segment, and operator confirmation. A floor-height measurement intersects the vertical line through the tapped target with this confirmed plane. It records the floor intersection and target point separately, along with the floor snapshot used. It is a gravity-aligned height; a tilted floor's perpendicular distance is a different quantity. The app does not infer tag identity from a height tap.

Version 0.3.1 separates floor scanning from confirmation. A live selected candidate is not the measurement datum until the operator presses Done with enough coverage and current normal tracking. Manual distance, floor-height and tag-width probes are blocked until a floor is confirmed; the final floor snapshot is retained in `floorConfirmed` and subsequent measurement records. Re-entering Measure can reuse a confirmed floor in the same AR coordinate segment.

Completed measurements are immutable: later plane refinement or another selected floor does not rewrite their original endpoints or numeric values. `measurementsAtStart` events include existing live geometry so measurements taken before Start are also retained in the resulting recording. This snapshot contains their geometry/provenance, including source-point camera pose, intrinsics, image/depth dimensions, display transforms and sampled depth/confidence; it does not retroactively capture RGB or depth buffers from before recording began. `floorConfirmed`, `measurementCompleted`, `measurementsCleared`, and `measurementsInvalidated` events record floor selection, measurement creation, clearing and coordinate-segment invalidation. Follow event order when reconstructing what was visible, and retain invalidated measurements as historical evidence rather than placing them in a new segment.

The live overlay is projected from world coordinates through the current AR camera, intrinsics, display transform and view zoom. Brief limited tracking hides it and prevents new taps without erasing completed measurements in the same segment. Coordinate resets, interruptions, backgrounding and native-view detachment invalidate live placement. The exported data remains available for offline review; this release does not save/relocalize an AR world map or restore 3D placement after app restart. Both measurement endpoints require usable, finite scene depth and medium/high confidence for direct depth taps; the computed floor intersection is explicitly derived from the selected plane, not presented as another measured depth sample.

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

Play opens the saved camera video with native AVKit controls. It does not yet render historical tag/measurement overlays. Share uses the persistent MP4; it is no longer a packaging step. Legacy sessions are prepared lazily, using their first frame to infer presentation rotation, while preserving byte-exact source restoration.
