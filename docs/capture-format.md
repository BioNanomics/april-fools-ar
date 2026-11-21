# Milestone 0 capture format

Schema version 1 is an exploratory capture format. Preserve the complete exported ZIP so later analysis has the original inputs. It is not a calibrated field map.

## Files and clocks

Each session has a UUID directory containing `manifest.json`, `frames.jsonl`, `events.jsonl`, `rgb.mp4`, `frames/`, and `depth/`. JSONL contains one JSON object per line. UTF-8 text, meters, and seconds are used unless a field says otherwise.

`ARFrame.timestamp` is a monotonic time in seconds since system boot. It is not Unix time. `createdAt` and event `wallTime` are ISO-8601 wall-clock annotations. Video presentation timestamps are relative to `firstARFrameTimestamp`; a frame's `videoPTSSeconds` supplies that correspondence. Only entries with `videoAppended: true` were accepted by the video writer. Do not assume consecutive metadata entries correspond to consecutive video frames.

`frameId` identifies the source camera frame within the app process. `segmentId` identifies the current AR coordinate segment; interruption/reset boundaries invalidate previously selected endpoints. Do not compare world points from different segments as if their world frames were identical.

## RGB and geometry

RGB video uses H.264, targeting 30 fps. Selected frames are JPEGs at a target of 5 Hz and at measurement/bookmark events, subject to the bounded writer queue. The preserved sensor image is not rotated to match the phone screen. `imageWidth`, `imageHeight`, `interfaceOrientation`, `viewportWidth`, `viewportHeight`, and `displayTransform` describe presentation.

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

AprilTag analysis uses the `tag36h11` family and the shared native AprilTag 3 detector. Each `aprilTagDetections` event identifies its source frame, coordinate segment, timestamp, image dimensions, intrinsics, camera pose and display transform. `detections` contains ID, family, Hamming corrections, decision margin, image-pixel center and four ordered image-pixel corners. An empty array with `analysisSucceeded: true` means the detector analyzed that frame and found no tags; it is distinct from a frame that was not analyzed or a failed analysis. Failures have `analysisSucceeded: false` and `detectorError`. The bounded analysis worker targets 8 Hz and records its latency. Live outlines are cleared when their result becomes stale. A detected ID is not proof of correct field placement, and the initial detector does not estimate a tag pose or assume a printed tag size.

`events.jsonl` includes bookmarks, selected measurement endpoints, tracking changes, segment boundaries, and session lifecycle events. An endpoint records its image/depth pixel, camera-frame identity, world point, confidence when available, and depth source. With two valid endpoints in one segment, the app reports 3D Euclidean distance and signed `second.y - first.y` vertical difference separately. The vertical difference is not automatically floor-to-tag height.

The writer retains at most three frames for disk work. Busy queues can omit frames or event snapshots; omissions are reported rather than assigned invented data. Capture counters distinguish accepted metadata, video, depth samples, and writer/video drops. Sample rates are targets, not guarantees.

Only a fully written manifest has `finalized: true`. Its `fileInventory` gives each payload file's relative path, byte length, and SHA-256. The manifest excludes itself from the inventory. A failed or interrupted finalization remains unavailable for normal export. Check `errors` as well as `finalized`.

ZIP export uses streaming, uncompressed ZIP entries and supports bundles below 4 GiB. Start with short sessions, export them, and verify their contents before a longer field visit. The export adds temporary storage roughly equal to the session size; the original stays on the phone.

Validate an exported bundle or copied session directory with:

```sh
python3 scripts/inspect-session.py /path/to/session.zip
```

For the short device check with a known visible tag, add `--require-tags` to fail when the export contains no decoded tag.

This checks readability, numeric buffer sizes, sample decoding, and payload checksums. It does not establish measurement accuracy or replace the field review.
