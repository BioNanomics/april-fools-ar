# Shared core extraction validation

Date: November 22, 2026. Library version 0.1.0, C ABI 1. This records code/build and generated-input evidence; no physical device or robot session was started.

## Portable implementation

- Seven CTest executables passed: geometry, measurements, projection, the existing AprilTag image/pose tests, a C++ consumer and a Java/JNI consumer.
- Geometry and measurement tests also passed AddressSanitizer/UndefinedBehaviorSanitizer checks. The C headers passed C11 compilation.
- A separately configured CMake `find_package(AFSpatialCore)` consumer compiled, linked and ran against the installed package.
- CPack produced `AFSpatialCore-0.1.0-Darwin.tar.gz` at `/tmp/april-fools-shared-core/build/spatial-core-portable-final/`.
- Reproduce with `./scripts/test-spatial-core.sh`. Tests retain assertions in Release builds.

## iOS adapter

- Existing simulator regression suite: **119 tests, zero failures**, including floor fit/leveling, height, source expiry, range conventions, projection/clipping, multi-tag overlays and settings. Result: `/tmp/afsc-ios-regression-1/Results.xcresult`.
- Six build-info/recorder tests passed, including saved calculation-core version/ABI and matching source build identity. Result: `/tmp/afsc-build-info-tests/Results.xcresult`.
- Simulator test bundles compile the same core source used in the app. No sensor accuracy or physical acquisition is claimed by these tests.
- The initial isolated app build exposed local environment issues: stale Homebrew Node, missing generated React Native files and Metro visibility of symlinked dependencies. Validation uses NVM Node22 and isolated copied dependencies. These were build-environment issues, not changed measurement behavior.

## Recording compatibility

Thirteen replay tests passed with Node22 and the current MP4 exporter/extractor from the working repository:

```sh
AFSC_LIBRARY=/tmp/april-fools-shared-core/build/spatial-core/libaf_spatial_core.dylib \
AFSC_RECORDING_TOOLS_ROOT=/Users/horner/prj/april-fools-ar \
python3 scripts/tests/test_spatial_core_replay.py -v
```

The MP4 test creates clean H.264 media, packages the source files through the existing Node writer, imports via the existing extractor, replays observations and compares them with directory/ZIP replay. It verifies exact restored file bytes, including the source MP4 and Float32 NaN/negative-zero bytes, source app identity, out-of-time-order events, reused frame IDs across segments, missing depth and metadata-only frames. Corrupt packages, unsafe ZIP paths, source-contained output, malformed metadata and duplicate frame identities are rejected. Explicit null floor selection is not replaced by stale recorded floor data. Missing historical frame age is reported as unavailable.

The separate container contract stays in `recording-format/FORMAT.md`. This change does not fork its writer or extractor. Source timestamps remain distinct from MP4 metadata packet timing and movie PTS. Full offline video-overlay playback remains future work.

## Robot and Android builds

- Exact OpenSDK **v2027-1 / GCC14.3.0** Systemcore toolchain archive verified against its published SHA256. Release and Debug core, JNI and C++ consumers crosscompiled as AArch64 Linux.
- `./gradlew :wpilib-cpp:build :wpilib-java:build` passed with **GradleRIO 2027.0.0-alpha-8** and Java25; the C++ consumer links in the Systemcore build. Local Maven packages include `linuxsystemcore` artifacts. These are build checks, not robot execution.
- Android **NDK r27c / 27.2.12479018**, Clang18.0.3, API24: ARM64 JNI/core compiled and linked. ELF class, machine and seven JNI exports verified. Artifact: `/tmp/april-fools-shared-core/build/android-arm64/libaf_spatial_core_jni.so`; SHA256 `7b87c89070f048fdea91c279a9fd55ef2345fa822b460bbdb14676517634caca`.
- Android AAR packaging has a configured Gradle/CI job but was not run locally because the Android platform SDK was absent. Full Android application/ARCore capture is not implemented by the binding module.
- CI includes desktop, Systemcore and Android package jobs. Those jobs were authored here; a hosted CI run has not been triggered or reported as passed.

## Remaining physical acceptance

A tester still needs to run the updated phone acquisition, export a real field recording, compare replay with live measurements, and execute the robot consumer on the matched Systemcore image. The extraction does not establish real-world accuracy, thermal behavior or sensor latency. The M0 field-data gate and SC.T remain open.
