# Shared spatial calculation core

One C/C++ implementation serves the iOS app, desktop recording replay, robot programs and Android JNI. The public interface is plain C (`include/afsc.h`); it contains no ARKit, UIKit, React Native, WPILib, Java or Android types. C++17 is the library baseline; the 2027 WPILib consumers use their required C++23/Java 25 toolchains.

## Boundaries

| Component | Owns |
| --- | --- |
| Existing AprilTag C core | tag36h11 detection, calibrated pose candidates, ambiguity and reprojection error |
| Shared measurement core | Euclidean camera ranges, optical-depth differences, validity policy, gravity-vertical floor height, gravity-relative tag orientation |
| Shared geometry core | deterministic robust floor fit, floor tilt/coverage, distance, vertical foot and floor patch corners |
| Shared projection core | camera projection, near-plane/viewport clipping of points, segments and polygons |
| iOS adapter | ARKit/CoreVideo acquisition, camera-axis conversion, settings, recorded metadata and native drawing |
| Robot/Android adapter | sensor acquisition, time/frame mapping, library loading and native presentation/telemetry |

Inputs may omit depth. Qualified tag geometry remains usable as an explicit height fallback. A known depth mismatch blocks that fallback. The core does not assume that every device has AR tracking, LiDAR or a floor; the adapter supplies availability and tracking usability. The spatial math core does not apply the app's optional presentation Kalman filter and introduces no new sensor-fusion policy. Raw IMU and wheel-odometry fusion remain future work.

## Numerical and observation contract

- Lengths are metres; new AFSC math API angles are radians. The retained AprilTag C API keeps its explicitly named `*Degrees` fields. Existing capture/UI degree fields are converted by the Swift adapter and remain backward compatible.
- Raw AprilTag camera coordinates are optical +X right, +Y down, +Z forward. The spatial world convention remains gravity-aligned +Y up. These differ from FTC camera +X right/+Y forward/+Z up and FRC NWU +X forward/+Y left/+Z up. Robot body/field frames require explicit transforms; an AR world is not a surveyed field frame.
- Matrices are column-major. `T_destination_source` maps source coordinates to destination coordinates. ARKit conversion is `T_world_optical = T_world_ARCamera * diag(1,-1,-1,1)`.
- 3D Euclidean camera distance, optical-axis Z, FTC camera-planar range and gravity-relative floor height are separate quantities. A depth sample is axial Z until unprojected with the exact source camera model.
- `AFSCObservationHeader` carries borrowed sensor/calibration/frame/segment/clock identities and nanosecond time for future typed streams. The current stateless height call explicitly labels its existing `*_s` fields in seconds. Conversion from recorded seconds must be explicit; never reinterpret seconds as nanoseconds or mix independent device clocks.
- Current frame/segment strings remain intact in the recording adapter; no hash substitutes for their identity. A reset invalidates coordinates in the old segment.
- Confidence categories are not covariance. Missing uncertainty is unknown, not zero. ARKit pose and depth are processed observations; their correlations must be considered before adding fusion.
- Arrays/pointers are borrowed only during the call. Caller owns buffers. No core function retains input pointers. Header version is `AFSC_ABI_VERSION=1`; incompatible layout changes require a new ABI version.
- Floor fitting uses the existing 32–512 sample bounds, fixed seed, 128 hypotheses, three refinements and rejection policy. Geometry/projection work has bounded storage. The existing detector may allocate internally and must be called serially per detector instance.

`afsc_gravity_orientation` composes the matching frame's `world_from_optical` rotation with `optical_from_tag_rotation`. The latter is a column-major homogeneous pure rotation with zero translation. The output retains the composed rotation, unit printed-up (`-tag Y`) and into-print normal (`+tag Z`) directions. `tilt_from_vertical_rad` is an unsigned plane lean: zero for a vertical plane and pi/2 for a horizontal plane. `twist_rad` measures clockwise rotation of the printed square relative to gravity projected into its plane, as seen from the printed front. Twist is unavailable when that projection's magnitude is <=1e-4; the plane lean remains available. Gravity establishes no absolute field heading.

Orientation requires usable tracking, an identified source frame no more than 0.4 seconds old, proper rigid rotations, a resolved visual pose, and passing range/incidence/decode/reprojection gates. It consumes no floor, depth, center pixel, image intrinsics or optical-axis offset. Auto sizing can independently require scene depth before the source pose is resolved. Only `max_range_m`, `max_plane_angle_rad` and `max_reprojection_rms_px` from the measurement settings apply; missing depth thresholds have no effect. A computed orientation describes that source frame and must expire or be invalidated with it in the adapter. The standalone `gravity_orientation_test` covers independently constructed tag lean/twist, horizontal-plane twist unavailability, invariance while the phone rotates and moves, and invalid or stale inputs.

## Camera pose display conventions

The additive portable `AFTagPoseConventions.h` interface derives FTC SDK or FRC / PhotonVision readouts from the full raw optical `R,t`. CMake builds the implementation into the shared/static libraries and installs this header beside `AFTagCore.h` under `include/afsc/`. Its matrices are explicitly **row-major** and angles **degrees**, matching the retained AprilTag API, whereas AFSC's general matrices are column-major and angles radians. Conversions must respect that boundary. The `AFSC_ABI_VERSION` layouts and all original optical/measurement quantities retain their meanings.

The iOS `TagPoseReadout` adapter selects `rawOptical`, `ftcSdk` or `frcPhotonVision` independently of tag-size mode and field package identity. New derived records name both frames and use reference `tag-relative-to-camera`. FTC Pitch/Roll/Yaw and FRC Roll/Pitch/Yaw are extracted from the full transformed matrix, not relabeled optical Euler values. A head-on raw identity yields FTC zero angles but PhotonVision pose yaw 180°. FTC planar range excludes camera-relative up; all profiles retain full 3D camera distance separately.

The JNI/robot consumers continue to expose their documented raw optical/spatial contracts; choosing an iOS display preference does not change a native observation's axes. Do not pass an optical vector or an AR world +Y-up vector into WPILib NWU types as if the bases matched. Apply camera-to-robot extrinsics and field alignment explicitly. See [decision 004](../../docs/decisions/004-pose-conventions.md) for matrices and SDK references.

Gravity-relative `tilt_from_vertical_rad` and `twist_rad` retain their existing definitions and ABI names. The UI now calls them **Lean** and **Upright**, explicitly app-derived measurements independent of SDK Euler conventions. The capture adapter adds `planeLeanFromVerticalDegrees` / `uprightRotationClockwiseDegrees` beside the unchanged legacy degree aliases. Raw diagnostic aliases formerly called “center bearing” remain unsigned optical-axis offsets; signed FTC horizontal bearing is a separate derived field.

## Build and test

```sh
./scripts/test-spatial-core.sh
```

Run from the repository root. Requires CMake, a C/C++ toolchain and a JDK. This builds static/shared libraries, executes native and actual Java/JNI numerical tests, checks generated JNI headers and installs a relocatable CMake package. See [robot instructions](../../robot/README.md) for the exact Systemcore SDK and WPILib consumers, and [Android instructions](../../bindings/android/README.md) for the native library package.

The app compiles `src/*.cpp` directly through `scripts/configure-ios.rb`, with Swift calling the C API through its existing bridging header. Its independent simulator harnesses link those same source files. The renderer continues to own native fonts, accessibility and touch handling.

## Recording import, export and extraction

Use the existing [recording-format contract](../../recording-format/FORMAT.md). The core does not introduce another MP4 layout or a second archive extractor:

1. The phone stores the original session folder. Exports preserve clean H.264 video and the `afar.session`, `afar.frames`, `afar.events`, `afar.files` tracks.
2. MP4 import delegates to `recording-format/npm/src/cli.mjs unpack`, which verifies and restores original files. Legacy ZIP and directory inputs remain supported.
3. Replay reads original `events.jsonl` in completion order, using each event's source-frame camera calibration. It never associates observations by the nearest movie time or a later camera frame.
4. Replay writes a **new** JSONL result. Raw detections, frame/segment identity, original timestamps and video-appended state remain alongside recomputed results. Input recordings are never rewritten.

```sh
python3 scripts/replay-spatial-core.py capture.mp4 \
  --core-library build/spatial-core/libaf_spatial_core.dylib \
  --output replay-results.jsonl
```

Use `.so` on Linux. MP4 input requires Node 22+ and `npm ci --prefix recording-format/npm`. The same command accepts a finalized session directory or legacy ZIP. It rejects existing destinations, output inside the source directory, unsafe paths, failed inventory checks and unsupported capture/core schemas.

New captures include `calculationCore` identity in the manifest and detection events. Each detection event includes the exact `floorSnapshot` (including explicit null when none was confirmed); floor-height diagnostics include `frameAgeSeconds`. Older exports still replay distances/quality, but a missing recorded frame age is reported as `sourceFrameAgeUnavailable` for full height-policy replay. No fabricated timing makes old data look complete.

MP4 metadata packet times are storage timing. Sensor time is the original record timestamp/clock; `videoPTSSeconds` and `videoAppended` remain separate. A frame with `videoAppended:false` may still contain a valid observation. Normal movie conversion can discard metadata; the original MP4 is the analysis artifact. Full offline video-overlay playback is not implemented by this library.

For round-trip verification:

```sh
AFSC_LIBRARY=build/spatial-core/libaf_spatial_core.dylib \
  python3 scripts/tests/test_spatial_core_replay.py -v
```

The tests exercise byte-exact source restoration, missing depth, height, source event ordering, repeated frame IDs across segments, missing historical timing, invalid inputs and corruption rejection. Their generated media establishes transport/calculation behavior, not real sensor accuracy.
