# Android native library

This is an Android library module (AAR), not an Android app. It shares the Java
source and stateless JNI implementation with `robot/java`. It has no ARCore,
camera, Activity, permission, recording, or tracking dependencies.
It lives under `bindings/android` so React Native does not discover it as a root
Android app when configuring the existing iOS application.

With JDK 17+, Android SDK 35, NDK 27.2.12479018, CMake 3.22.1 and Gradle 8.13:

```sh
cd bindings/android
gradle assembleRelease
```

An Android consumer calls `System.loadLibrary("af_spatial_core_jni")` once before
calling `com.aprilfools.spatial.SpatialCore`. Input points use metres, gravity +Y
up; AprilTag camera poses use optical +X right, +Y down, +Z forward. A platform
adapter must convert ARCore coordinates, supply frame/calibration identities,
and enforce observation quality before displaying accepted measurements. The
geometric `floorHeight` binding by itself makes no tracking-quality guarantee.
