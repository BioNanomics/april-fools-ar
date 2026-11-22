#include "com_aprilfools_spatial_SpatialCore.h"
#include "afsc_geometry.h"
#include "AFTagCore.h"
#include <array>
#include <cmath>

namespace {
void invalid(JNIEnv* env, const char* text) {
    const auto type = env->FindClass("java/lang/IllegalArgumentException");
    if (type) env->ThrowNew(type, text);
}
template <size_t N> bool read(JNIEnv* env, jdoubleArray input, std::array<double, N>& out) {
    if (!input || env->GetArrayLength(input) != static_cast<jsize>(N)) {
        invalid(env, "Array has the wrong length"); return false;
    }
    env->GetDoubleArrayRegion(input, 0, N, out.data());
    if (env->ExceptionCheck()) return false;
    for (double value : out) if (!std::isfinite(value)) {
        invalid(env, "Array contains a nonfinite value"); return false;
    }
    return true;
}
AFSCVec3 point(const std::array<double, 3>& p) { return {p[0], p[1], p[2]}; }
template <size_t N> jdoubleArray output(JNIEnv* env, const std::array<double, N>& values) {
    const auto result = env->NewDoubleArray(N);
    if (result) env->SetDoubleArrayRegion(result, 0, N, values.data());
    return result;
}
bool foot(JNIEnv* env, jdoubleArray t, jdoubleArray o, jdoubleArray n,
          AFSCVec3& target, AFSCVec3& result) {
    std::array<double, 3> tv{}, ov{}, nv{};
    if (!read(env, t, tv) || !read(env, o, ov) || !read(env, n, nv)) return false;
    target = point(tv);
    if (afsc_vertical_foot(target, {point(ov), point(nv)}, &result) != AFSC_GEOMETRY_OK) {
        invalid(env, "Floor plane or target is outside supported geometry"); return false;
    }
    return true;
}
}

JNIEXPORT jint JNICALL Java_com_aprilfools_spatial_SpatialCore_abiVersion(JNIEnv*, jclass) {
    return static_cast<jint>(afsc_abi_version());
}
JNIEXPORT jstring JNICALL Java_com_aprilfools_spatial_SpatialCore_version(JNIEnv* env, jclass) {
    return env->NewStringUTF(afsc_version());
}
JNIEXPORT jdoubleArray JNICALL Java_com_aprilfools_spatial_SpatialCore_distance(
    JNIEnv* env, jclass, jdoubleArray start, jdoubleArray end) {
    std::array<double, 3> s{}, e{}; AFSCDistance result{};
    if (!read(env, start, s) || !read(env, end, e)) return nullptr;
    if (afsc_distance(point(s), point(e), &result) != AFSC_GEOMETRY_OK) {
        invalid(env, "Invalid distance geometry"); return nullptr;
    }
    return output<3>(env, {result.distance_meters, result.vertical_meters, result.horizontal_meters});
}
JNIEXPORT jdoubleArray JNICALL Java_com_aprilfools_spatial_SpatialCore_verticalFoot(
    JNIEnv* env, jclass, jdoubleArray t, jdoubleArray o, jdoubleArray n) {
    AFSCVec3 target{}, result{};
    if (!foot(env, t, o, n, target, result)) return nullptr;
    return output<3>(env, {result.x, result.y, result.z});
}
JNIEXPORT jdouble JNICALL Java_com_aprilfools_spatial_SpatialCore_floorHeight(
    JNIEnv* env, jclass, jdoubleArray t, jdoubleArray o, jdoubleArray n) {
    AFSCVec3 target{}, result{};
    if (!foot(env, t, o, n, target, result)) return 0;
    return target.y - result.y;
}
JNIEXPORT jdoubleArray JNICALL Java_com_aprilfools_spatial_SpatialCore_fitFloor(
    JNIEnv* env, jclass, jdoubleArray xyz, jdouble x, jdouble z) {
    if (!xyz || !std::isfinite(x) || !std::isfinite(z)) {
        invalid(env, "Floor data or reference is missing/nonfinite"); return nullptr;
    }
    const jsize length = env->GetArrayLength(xyz);
    if (length < 32 * 3 || length > 512 * 3 || length % 3 != 0) {
        invalid(env, "Floor data requires 32..512 xyz triples"); return nullptr;
    }
    std::array<double, 512 * 3> copied{};
    env->GetDoubleArrayRegion(xyz, 0, length, copied.data());
    if (env->ExceptionCheck()) return nullptr;
    std::array<AFSCVec3, 512> points{};
    for (jsize i = 0; i < length; i += 3) {
        for (int j = 0; j < 3; ++j) if (!std::isfinite(copied[i + j])) {
            invalid(env, "Floor data contains a nonfinite value"); return nullptr;
        }
        points[i / 3] = {copied[i], copied[i + 1], copied[i + 2]};
    }
    AFSCFloorFit result{};
    if (afsc_floor_fit(points.data(), length / 3, {x, z}, &result) != AFSC_GEOMETRY_OK) {
        invalid(env, "Floor fit did not meet the core quality criteria"); return nullptr;
    }
    return output<10>(env, {result.plane.origin.x, result.plane.origin.y, result.plane.origin.z,
        result.plane.normal.x, result.plane.normal.y, result.plane.normal.z, result.tilt_radians,
        static_cast<double>(result.sample_count), static_cast<double>(result.inlier_count), result.rms_meters});
}
JNIEXPORT jdoubleArray JNICALL Java_com_aprilfools_spatial_SpatialCore_estimateTagPose(
    JNIEnv* env, jclass, jdoubleArray corners, jdoubleArray calibration) {
    std::array<double, 8> c{}; std::array<double, 5> k{};
    if (!read(env, corners, c) || !read(env, calibration, k)) return nullptr;
    double ordered[4][2];
    for (size_t i = 0; i < 4; ++i) { ordered[i][0] = c[i * 2]; ordered[i][1] = c[i * 2 + 1]; }
    AFTagCalibration intrinsics{k[0], k[1], k[2], k[3], k[4]}; AFTagPose pose{};
    if (AFTagCoreEstimatePoseFromCorners(ordered, &intrinsics, &pose) != AFTagCoreSuccess) {
        invalid(env, "Tag pose is unavailable for these corners/calibration"); return nullptr;
    }
    std::array<double, 18> result{};
    for (size_t i = 0; i < 3; ++i) result[i] = pose.translation[i];
    for (size_t i = 0; i < 9; ++i) result[3 + i] = pose.rotationRowMajor[i];
    result[12] = pose.rangeMeters; result[13] = pose.reprojectionRMSEPixels;
    result[14] = pose.poseError; result[15] = pose.candidateCount;
    result[16] = pose.ambiguous; result[17] = pose.planeAngleDegrees;
    return output(env, result);
}
