# 003 — Portable calculation core and sensor adapters

Accepted by the user's implementation authorization on November 22, 2026.

Use a dependency-light C++17 numerical library behind a versioned plain C ABI. Keep the existing AprilTag C implementation and native iOS acquisition/rendering. The same compiled source serves Swift, C++ robot programs, Java/JNI, Android JNI and desktop replay. Compile separately for each target ABI.

Swift on ARM64 Linux is technically viable. It was not selected as the shared core because it adds Swift runtime/sysroot packaging and a custom GradleRIO integration. The C API avoids exposing either Swift or compiler-specific C++ types across language boundaries.

Verified 2027 target: WPILib/GradleRIO 2027.0.0-alpha-8, Systemcore AArch64 GNU/Linux, OpenSDK v2027-1 GCC14.3.0. This is prerelease tooling, independently pinned from the portable core. Consumer adapters isolate Java package/C++ namespace changes and timestamp conversions. Recheck image/vendor compatibility before hardware deployment; do not substitute a generic ARM64 SDK for the target sysroot.

Use the existing MP4/YAML/TAR export contract and extractor. Numerical replay is a consumer of original captures, not a container writer. Preserve source app/core versions, camera intrinsics, transforms, frame/segment identity, clock semantics, missing-data state and original event order. New source records add floor snapshot/frame age to make policy decisions reproducible without altering existing schema-1 fields.

Initial extraction preserves normal input behavior and existing rejection thresholds. Improved filtering, IMU/odometry fusion, full ARCore acquisition and offline video-overlay playback are separate features. Sensor estimates remain estimates; passing cross-platform calculations does not establish surveyed accuracy.

Primary references checked during the decision:

- [2027 Alpha 8 release](https://github.com/wpilibsuite/allwpilib/releases/tag/v2027.0.0-alpha-8)
- [2027 changes](https://docs.wpilib.org/en/latest/docs/yearly-overview/yearly-changelog.html)
- [Systemcore OpenSDK configuration](https://github.com/wpilibsuite/opensdk/tree/main/targets/systemcore)
- [Swift Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html)
- [Swift 6.3 C exports](https://www.swift.org/blog/swift-6.3-released/)

See [core documentation](../../native/SpatialCore/README.md) and [validation evidence](../validation/SC-shared-core.md).
