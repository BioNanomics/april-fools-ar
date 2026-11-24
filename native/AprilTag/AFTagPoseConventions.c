#include "AFTagPoseConventions.h"
#include <math.h>
#include <string.h>

static const double pi = 3.14159265358979323846264338327950288;

static int opticalPoseValid(const double *translation, const double *rotation) {
    if (!translation || !rotation) return 0;
    for (int i = 0; i < 3; ++i) if (!isfinite(translation[i])) return 0;
    if (translation[2] <= 0 || !isfinite(hypot(hypot(translation[0], translation[1]), translation[2]))) return 0;
    for (int i = 0; i < 9; ++i) if (!isfinite(rotation[i])) return 0;
    /* Match the solver's numerical acceptance tolerance; reject reflections. */
    for (int a = 0; a < 3; ++a) for (int b = 0; b < 3; ++b) {
        double dot = 0;
        for (int row = 0; row < 3; ++row) dot += rotation[3 * row + a] * rotation[3 * row + b];
        if (fabs(dot - (a == b ? 1.0 : 0.0)) > 1e-4) return 0;
    }
    double determinant = rotation[0] * (rotation[4] * rotation[8] - rotation[5] * rotation[7])
        - rotation[1] * (rotation[3] * rotation[8] - rotation[5] * rotation[6])
        + rotation[2] * (rotation[3] * rotation[7] - rotation[4] * rotation[6]);
    return isfinite(determinant) && fabs(determinant - 1.0) <= 1e-4;
}

/* Signed permutation of both bases, with an optional upstream-tag correction.
 * Rows of the new basis matrix have one signed nonzero at basisIndex[row]. */
static void changeBasis(const double *rotation, const int *basisIndex, const int *basisSign,
                        const int *tagCorrection, double *converted) {
    for (int row = 0; row < 3; ++row) for (int column = 0; column < 3; ++column) {
        int oldRow = basisIndex[row], oldColumn = basisIndex[column];
        converted[3 * row + column] = basisSign[row] * basisSign[column]
            * tagCorrection[oldColumn] * rotation[3 * oldRow + oldColumn];
    }
}

static float sdkDegrees(float radians) {
    float revolutions = radians / (float)pi;
    float degrees = revolutions * 180.0f;
    double value = degrees;
    while (value >= 180.0) value -= 360.0;
    while (value < -180.0) value += 360.0;
    return (float)value;
}

typedef struct { float pitch, roll, yaw; float magnitude; } SDKAngles;

/* Independently derived decomposition of R=Ry(a) Rx(b) Rz(c). As in the SDK,
 * a=-yaw, b=pitch, c=roll. The equivalent second solution is also considered.
 * Float casts and the normalization-before-negation order preserve SDK choices.
 */
static SDKAngles ftcAngles(const float *rotation, int alternative) {
    float pitchRadians, rollRadians, negatedYawRadians;
    float sinePitch = -rotation[5];
    if (sinePitch >= 1.0f) {
        pitchRadians = (float)(pi / 2);
        rollRadians = 0;
        negatedYawRadians = (float)-atan2((double)rotation[6], (double)rotation[0]);
    } else if (sinePitch <= -1.0f) {
        pitchRadians = (float)(-pi / 2);
        rollRadians = 0;
        negatedYawRadians = (float)atan2(-(double)rotation[1], (double)rotation[0]);
    } else {
        pitchRadians = (float)(alternative ? pi - asin((double)sinePitch) : asin((double)sinePitch));
        double cosinePitch = cos((double)pitchRadians);
        rollRadians = (float)atan2(rotation[3] / cosinePitch, rotation[4] / cosinePitch);
        negatedYawRadians = (float)atan2(rotation[2] / cosinePitch, rotation[8] / cosinePitch);
    }
    SDKAngles angles;
    angles.pitch = sdkDegrees(pitchRadians);
    angles.roll = sdkDegrees(rollRadians);
    angles.yaw = sdkDegrees(negatedYawRadians);
    /* Orientation chooses the shorter normalized float angle vector before the
     * AprilTag processor changes the sign of its first (yaw) angle. */
    float squared = angles.yaw * angles.yaw;
    squared = squared + angles.pitch * angles.pitch;
    squared = squared + angles.roll * angles.roll;
    angles.magnitude = (float)sqrt((double)squared);
    return angles;
}

int AFTagConvertOpticalPoseToFTC(const double translation[3], const double rotation[9], AFTagFTCPose *output) {
    if (!output) return 0;
    memset(output, 0, sizeof(*output));
    if (!opticalPoseValid(translation, rotation)) return 0;
    const int index[3] = {0, 2, 1}, sign[3] = {1, 1, -1}, correction[3] = {1, 1, 1};
    for (int i = 0; i < 3; ++i) output->translationMeters[i] = sign[i] * translation[index[i]];
    changeBasis(rotation, index, sign, correction, output->rotationRowMajor);
    float sdkRotation[9];
    for (int i = 0; i < 9; ++i) sdkRotation[i] = (float)rotation[i];
    SDKAngles principal = ftcAngles(sdkRotation, 0), alternate = ftcAngles(sdkRotation, 1);
    SDKAngles chosen = principal.magnitude <= alternate.magnitude ? principal : alternate;
    output->pitchDegrees = chosen.pitch;
    output->rollDegrees = chosen.roll;
    output->yawDegrees = -(double)chosen.yaw;
    output->eulerSingular = fabs((double)sdkRotation[5]) >= 1.0;
    output->planarRangeMeters = hypot(translation[0], translation[2]);
    output->bearingDegrees = atan2(-translation[0], translation[2]) * 180.0 / pi;
    output->elevationDegrees = atan2(-translation[1], translation[2]) * 180.0 / pi;
    return 1;
}

/* Unit quaternion from a proper rotation, choosing its best-conditioned
 * diagonal/trace branch. Euler identities below do not depend on its sign. */
static void quaternionFromRotation(const double *rotation, double *quaternion) {
    double trace = rotation[0] + rotation[4] + rotation[8];
    if (trace > 0) {
        double scale = 2 * sqrt(trace + 1);
        quaternion[0] = scale / 4;
        quaternion[1] = (rotation[7] - rotation[5]) / scale;
        quaternion[2] = (rotation[2] - rotation[6]) / scale;
        quaternion[3] = (rotation[3] - rotation[1]) / scale;
    } else {
        int largest = rotation[4] > rotation[0] ? 1 : 0;
        if (rotation[8] > rotation[3 * largest + largest]) largest = 2;
        int next = (largest + 1) % 3, last = (largest + 2) % 3;
        double scale = 2 * sqrt(1 + rotation[3 * largest + largest]
                               - rotation[3 * next + next] - rotation[3 * last + last]);
        quaternion[largest + 1] = scale / 4;
        quaternion[0] = (rotation[3 * last + next] - rotation[3 * next + last]) / scale;
        quaternion[next + 1] = (rotation[3 * largest + next] + rotation[3 * next + largest]) / scale;
        quaternion[last + 1] = (rotation[3 * largest + last] + rotation[3 * last + largest]) / scale;
    }
    double norm = hypot(hypot(quaternion[0], quaternion[1]), hypot(quaternion[2], quaternion[3]));
    for (int i = 0; i < 4; ++i) quaternion[i] /= norm;
}

int AFTagConvertOpticalPoseToFRC(const double translation[3], const double rotation[9], AFTagFRCPose *output) {
    if (!output) return 0;
    memset(output, 0, sizeof(*output));
    if (!opticalPoseValid(translation, rotation)) return 0;
    const int index[3] = {2, 0, 1}, sign[3] = {1, -1, -1}, correction[3] = {-1, 1, -1};
    for (int i = 0; i < 3; ++i) output->translationMeters[i] = sign[i] * translation[index[i]];
    changeBasis(rotation, index, sign, correction, output->rotationRowMajor);
    double quaternion[4];
    quaternionFromRotation(output->rotationRowMajor, quaternion);
    double w = quaternion[0], x = quaternion[1], y = quaternion[2], z = quaternion[3];
    double rollCosine = 1 - 2 * (x * x + y * y), rollSine = 2 * (w * x + y * z);
    double yawCosine = 1 - 2 * (y * y + z * z), yawSine = 2 * (w * z + x * y);
    double pitchSine = 2 * (w * y - z * x);
    double pitch = fabs(pitchSine) >= 1 ? copysign(pi / 2, pitchSine) : asin(pitchSine);
    int singularRoll = rollCosine * rollCosine + rollSine * rollSine <= 1e-20;
    int singularYaw = yawCosine * yawCosine + yawSine * yawSine <= 1e-20;
    output->rollDegrees = (singularRoll ? 0 : atan2(rollSine, rollCosine)) * 180 / pi;
    output->pitchDegrees = pitch * 180 / pi;
    output->yawDegrees = (singularYaw ? atan2(2 * w * z, w * w - z * z) : atan2(yawSine, yawCosine)) * 180 / pi;
    output->eulerSingular = singularRoll || singularYaw;
    output->euclideanRangeMeters = hypot(hypot(translation[0], translation[1]), translation[2]);
    return 1;
}
