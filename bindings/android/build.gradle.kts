plugins { id("com.android.library") version "8.13.1" }

android {
    namespace = "com.aprilfools.spatial"
    compileSdk = 35
    ndkVersion = "27.2.12479018"
    defaultConfig {
        minSdk = 24
        externalNativeBuild.cmake {
            arguments += listOf("-DAFSC_BUILD_JNI=ON", "-DBUILD_TESTING=OFF",
                "-DAFSC_BUILD_EXAMPLES=OFF", "-DAFSC_BUILD_SHARED=OFF")
            targets += "af_spatial_core_jni"
            cppFlags += "-std=c++17"
        }
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }
    sourceSets["main"].java.srcDir("../../robot/java/src/main/java")
    externalNativeBuild.cmake {
        path = file("../../native/SpatialCore/CMakeLists.txt")
        version = "3.22.1"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
