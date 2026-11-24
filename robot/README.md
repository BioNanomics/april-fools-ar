# Shared core robot consumers

The core uses C++17 behind a C ABI. `cpp/example.cpp` runs as a dependency-free
desktop consumer; `java/` is the common Java/JNI API also used by the Android AAR.
`wpilib-cpp` and `wpilib-java` are minimal **WPILib 2027.0.0-alpha-8** Systemcore
consumers using WPILib's C++23 and Java 25 toolchains. No robot hardware is needed
to compile them.

```sh
# Desktop numerical tests, JNI and generated-header parity
scripts/test-spatial-core.sh

# Exact OpenSDK v2027-1 Systemcore GCC 14.3 toolchain, not generic Linux ARM64
robot/build-systemcore.sh

# JDK 25 is required for WPILib. Set JAVA_HOME to that JDK first.
cd robot
PATH="$PWD/../build/toolchains/opensdk-v2027-1-arm64-apple-darwin/systemcore/bin:$PATH" \
  ./gradlew :wpilib-cpp:build :wpilib-java:build
```

`build-systemcore.sh` downloads the official archive for the current host and
checks its pinned SHA-256. Set `AFSC_SYSTEMCORE_TOOLCHAIN` to reuse an extracted
official toolchain. Adjust the host segment in the PATH example on Intel macOS
or Linux. GradleRIO discovers the prefixed compiler through PATH. Its CMake file
identifies `aarch64-systemcore2027-linux-gnu`.
The script builds real Release and Debug archives/JNI libraries and packages a
local Maven repository under `robot/build/maven` with the `linuxsystemcore`
classifier and `linux/systemcore/{static,shared}` layout. The consumer projects
resolve that repository through the checked-in vendordep. Nothing is published
remotely and no deployment task is run by these commands. Supply a real team
number when intentionally deploying with GradleRIO.

Only Systemcore binaries are advertised by the vendordep. The Android ABI and
generic Linux ARM64 ABI are deliberately separate artifacts. The JNI library
contains the core statically, with no host JVM library dependency. Java passes
bounded numeric arrays and receives owned arrays; there are no raw pointer
handles. Null, incorrect-length and nonfinite inputs are rejected.

Coordinates: metres, world +Y up; AprilTag poses use camera optical +X right,
+Y down, +Z forward. `floorHeight` exposes geometric height; a robot adapter must
validate tracking, calibration, timestamps and frame/segment identity before
accepting a measurement. No camera, transport, field-layout or NetworkTables
policy is included in this minimal consumer.

The WPILib consumers do not automatically convert the raw pose to WPILib's usual
X forward/Y left/Z up basis. In particular, a WPILib AprilTagPoseEstimator
transform retains the upstream optical frame. For PhotonVision-compatible
camera-relative tag presentation, the portable pose-convention helper applies
both EDN→NWU basis conversion and the tag-local Ry(π) correction; a head-on
upright tag has pose yaw 180°. FTC uses a different camera/tag basis and its own
Euler extraction, planar range, horizontal bearing and projected elevation.
Neither adapter supplies mounting extrinsics or field localization. The app's
saved display profile and Auto size inference do not change these consumer
contracts. See [explicit pose conventions](../docs/decisions/004-pose-conventions.md).

Upstream references checked for this integration:

- [WPILib 2027 alpha-8 generated templates](https://github.com/wpilibsuite/vscode-wpilib/releases/tag/v2027.0.0-alpha-8)
- [GradleRIO](https://github.com/wpilibsuite/GradleRIO)
- [2027 vendor template](https://github.com/wpilibsuite/vendor-template/tree/2027)
- [OpenSDK v2027-1](https://github.com/wpilibsuite/opensdk/releases/tag/v2027-1)

The Gradle wrapper and template conventions derive from those projects; see
`WPILib-License.md`. AprilTag notices are included in every native package.

Verified on macOS ARM64, 2026-11-22: CMake/CTest native and JNI numerical tests;
OpenSDK v2027-1 GCC 14.3 Release/Debug core, JNI and C++ consumer; full GradleRIO
alpha-8 C++ and Java builds (AArch64 ELF executables and Java 25 package); Android
NDK r27c ARM64 JNI at API 24. Cross-compiled binaries were inspected but were not
executed on Systemcore or Android hardware. The Android AAR Gradle packaging
task still requires a local Android SDK; only its actual NDK native target was
compiled in this verification.
