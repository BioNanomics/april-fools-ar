# Milestone 0 capture format

Schema version 1 is an exploratory capture format. Preserve the complete exported ZIP so later analysis has the original inputs. It is not a calibrated field map.

## Files and clocks

Each session has a UUID directory containing `manifest.json`, `frames.jsonl`, `events.jsonl`, `rgb.mp4`, `frames/`, and `depth/`. JSONL contains one JSON object per line. UTF-8 text, meters, and seconds are used unless a field says otherwise.

`ARFrame.timestamp` is a monotonic time in seconds since system boot. It is not Unix time. `createdAt` and event `wallTime` are ISO-8601 wall-clock annotations. Video presentation timestamps are relative to `firstARFrameTimestamp`; a frame's `videoPTSSeconds` supplies that correspondence. Only entries with `videoAppended: true` were accepted by the video writer. Do not assume consecutive metadata entries correspond to consecutive video frames.

`frameId` identifies the source camera frame within the app process. `segmentId` identifies the current AR coordinate segment; interruption/reset boundaries invalidate previously selected endpoints. Do not compare world points from different segments as if their world frames were identical.

## RGB and geometry

RGB video uses H.264, targeting 30 fps. Selected frames are JPEGs at a target of 5 Hz and at positive-detection/measurement/bookmark events, subject to the bounded writer queue. A frame already saved as a JPEG is reused rather than duplicated. The preserved sensor image is not rotated to match the phone screen. `imageWidth`, `imageHeight`, `interfaceOrientation`, `viewportWidth`, `viewportHeight`, and `displayTransform` describe presentation.

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

`debugSettings.showPoseAxes` is an optional display preference (default `false` when absent in older settings). It controls the projected tag-local RGB axis gizmo; it does not change the pose solution, tag size or raw recorded geometry.

View-zoom builds add `displayZoom` and `previewDisplayTransform` to frame and AprilTag-analysis metadata. `displayTransform` retains the original sensor-to-unzoomed-viewport mapping. `previewDisplayTransform` applies the centered display magnification after that mapping; it does not describe a different camera calibration. A measurement point's `viewNormalized` stays in the unzoomed viewport coordinates used to sample the image/depth, and its `displayZoom` records the factor used by that tap. Raw images, depth, intrinsics and solved poses retain their original conventions.

`events.jsonl` includes bookmarks, selected measurement endpoints, tracking changes, segment boundaries, and session lifecycle events. An endpoint records its image/depth pixel, camera-frame identity, world point, confidence and depth source. With two valid endpoints in one segment, the app reports 3D Euclidean distance and signed `second.y - first.y` vertical difference separately. The vertical difference is not automatically floor-to-tag height.

Version 0.2.0 adds explicit floor selection and persistent spatial measurements. A floor selection retains the estimated plane boundary, world-space origin/normal, source frame/segment, and operator confirmation. A floor-height measurement intersects the vertical line through the tapped target with this confirmed plane. It records the floor intersection and target point separately, along with the floor snapshot used. It is a gravity-aligned height; a tilted floor's perpendicular distance is a different quantity. The app does not infer tag identity from a height tap.

Completed measurements are immutable: later plane refinement or another selected floor does not rewrite their original endpoints or numeric values. `measurementsAtStart` events include existing live geometry so measurements taken before Start are also retained in the resulting recording. This snapshot contains their geometry/provenance, including source-point camera pose, intrinsics, image/depth dimensions, display transforms and sampled depth/confidence; it does not retroactively capture RGB or depth buffers from before recording began. `floorConfirmed`, `measurementCompleted`, `measurementsCleared`, and `measurementsInvalidated` events record floor selection, measurement creation, clearing and coordinate-segment invalidation. Follow event order when reconstructing what was visible, and retain invalidated measurements as historical evidence rather than placing them in a new segment.

The live overlay is projected from world coordinates through the current AR camera, intrinsics, display transform and view zoom. Brief limited tracking hides it and prevents new taps without erasing completed measurements in the same segment. Coordinate resets, interruptions, backgrounding and native-view detachment invalidate live placement. The exported data remains available for offline review; this release does not save/relocalize an AR world map or restore 3D placement after app restart. Both measurement endpoints require usable, finite scene depth and medium/high confidence for direct depth taps; the computed floor intersection is explicitly derived from the selected plane, not presented as another measured depth sample.

The writer retains at most three frames for disk work. Busy queues can omit frames or event snapshots; omissions are reported rather than assigned invented data. Capture counters distinguish accepted metadata, video, depth samples, and writer/video drops. Sample rates are targets, not guarantees.

Only a fully written manifest has `finalized: true`. Its `fileInventory` gives each payload file's relative path, byte length, and SHA-256. The manifest excludes itself from the inventory. A failed or interrupted finalization remains unavailable for normal export. Check `errors` as well as `finalized`.

ZIP export uses streaming, uncompressed ZIP entries and supports bundles below 4 GiB. Start with short sessions, export them, and verify their contents before a longer field visit. The export adds temporary storage roughly equal to the session size; the original stays on the phone.

Validate an exported bundle or copied session directory with:

```sh
python3 scripts/inspect-session.py /path/to/session.zip
```

For the short device check with a known visible tag, add `--require-tags` to fail when the export contains no decoded tag.

This checks readability, numeric buffer sizes, sample decoding, and payload checksums. It does not establish measurement accuracy or replace the field review.
