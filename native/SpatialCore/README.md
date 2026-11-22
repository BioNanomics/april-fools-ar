# Shared spatial calculation core

One C/C++ implementation serves the iOS app, desktop recording replay, robot programs and Android JNI. The public interface is plain C (`include/afsc.h`); it contains no ARKit, UIKit, React Native, WPILib, Java or Android types. C++17 is the library baseline; the 2027 WPILib consumers use their required C++23/Java 25 toolchains.

## Boundaries

| Component | Owns |
| --- | --- |
| Existing AprilTag C core | tag36h11 detection, calibrated pose candidates, ambiguity and reprojection error |
| Shared measurement core | Euclidean camera ranges, optical-depth differences, validity policy, gravity-vertical floor height |
| Shared geometry core | deterministic robust floor fit, floor tilt/coverage, distance, vertical foot and floor patch corners |
| Shared projection core | camera projection, near-plane/viewport clipping of points, segments and polygons |
| iOS adapter | ARKit/CoreVideo acquisition, camera-axis conversion, settings, recorded metadata and native drawing |
| Robot/Android adapter | sensor acquisition, time/frame mapping, library loading and native presentation/telemetry |

Inputs may omit depth. Qualified tag geometry remains usable as an explicit height fallback. A known depth mismatch blocks that fallback. The core does not assume that every device has AR tracking, LiDAR or a floor; the adapter supplies availability and tracking usability. No Kalman filter or new sensor-fusion policy was introduced in this extraction. Raw IMU and wheel-odometry fusion remain future work.

## Numerical and observation contract

- Lengths are metres; core angles are radians. Existing capture/UI degree fields are converted by the Swift adapter and remain backward compatible.
- Camera optical coordinates are +X right, +Y down, +Z forward. The current world convention is gravity-aligned +Y up. Robot body/field frames must be explicitly transformed; an AR world is not a surveyed field frame.
- Matrices are column-major. `T_destination_source` maps source coordinates to destination coordinates. ARKit conversion is `T_world_optical = T_world_ARCamera * diag(1,-1,-1,1)`.
- Euclidean range, optical-axis Z and floor height are separate quantities. A depth sample is axial Z until unprojected with the exact source camera model.
- `AFSCObservationHeader` carries borrowed sensor/calibration/frame/segment/clock identities and nanosecond time for future typed streams. The current stateless height call explicitly labels its existing `*_s` fields in seconds. Conversion from recorded seconds must be explicit; never reinterpret seconds as nanoseconds or mix independent device clocks.
- Current frame/segment strings remain intact in the recording adapter; no hash substitutes for their identity. A reset invalidates coordinates in the old segment.
- Confidence categories are not covariance. Missing uncertainty is unknown, not zero. ARKit pose and depth are processed observations; their correlations must be considered before adding fusion.
- Arrays/pointers are borrowed only during the call. Caller owns buffers. No core function retains input pointers. Header version is `AFSC_ABI_VERSION=1`; incompatible layout changes require a new ABI version.
- Floor fitting uses the existing 32–512 sample bounds, fixed seed, 128 hypotheses, three refinements and rejection policy. Geometry/projection work has bounded storage. The existing detector may allocate internally and must be called serially per detector instance.

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
