#include "AFTagCore.h"
#include "apriltag.h"
#include "apriltag_pose.h"
#include "common/homography.h"
#include "tag36h11.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

struct AFTagCore {
    apriltag_detector_t *detector;
    apriltag_family_t *family;
};

static int calibrationValid(const AFTagCalibration *k) {
    // Broad numerical-safety bounds, not an accuracy envelope or device claim.
    return k && isfinite(k->fx) && isfinite(k->fy) && isfinite(k->cx) && isfinite(k->cy) &&
        isfinite(k->tagSizeMeters) && k->fx >= 1e-3 && k->fy >= 1e-3 &&
        k->fx <= 1e8 && k->fy <= 1e8 && fabs(k->cx) <= 1e8 && fabs(k->cy) <= 1e8 &&
        k->tagSizeMeters >= 1e-6 && k->tagSizeMeters <= 1e3;
}

static int cornersValid(const double p[4][2]) {
    if (!p) return 0;
    double previousCross = 0;
    for (int i = 0; i < 4; i++) {
        int j = (i + 1) % 4, k = (i + 2) % 4;
        if (!isfinite(p[i][0]) || !isfinite(p[i][1]) || fabs(p[i][0]) > 1e8 || fabs(p[i][1]) > 1e8)
            return 0;
        double cross = (p[j][0] - p[i][0]) * (p[k][1] - p[j][1]) -
                       (p[j][1] - p[i][1]) * (p[k][0] - p[j][0]);
        if (!isfinite(cross) || fabs(cross) < 1e-8 || (i && cross * previousCross <= 0)) return 0;
        previousCross = cross;
    }
    return 1;
}

static double clamped(double value, double low, double high) {
    return fmax(low, fmin(high, value));
}

static int poseCandidate(const apriltag_pose_t *candidate, double error,
                         const apriltag_detection_t *detection, const AFTagCalibration *k,
                         AFTagPose *result) {
    if (!candidate->R || !candidate->t || !isfinite(error) || error < 0) return 0;
    memset(result, 0, sizeof(*result));
    for (int i = 0; i < 3; i++) {
        result->translation[i] = MATD_EL(candidate->t, i, 0);
        if (!isfinite(result->translation[i])) return 0;
        for (int j = 0; j < 3; j++) {
            double value = MATD_EL(candidate->R, i, j);
            if (!isfinite(value)) return 0;
            result->rotationRowMajor[3 * i + j] = value;
        }
    }
    const double *r = result->rotationRowMajor, *t = result->translation;
    if (t[2] <= 1e-9) return 0;
    double determinant = r[0] * (r[4] * r[8] - r[5] * r[7]) -
        r[1] * (r[3] * r[8] - r[5] * r[6]) + r[2] * (r[3] * r[7] - r[4] * r[6]);
    if (!isfinite(determinant) || fabs(determinant - 1) > 1e-4) return 0;
    for (int a = 0; a < 3; a++) for (int b = 0; b < 3; b++) {
        double dot = r[a] * r[b] + r[3 + a] * r[3 + b] + r[6 + a] * r[6 + b];
        if (fabs(dot - (a == b ? 1 : 0)) > 1e-4) return 0;
    }
    const double signs[4][2] = {{-1, 1}, {1, 1}, {1, -1}, {-1, -1}};
    double squaredPixels = 0, half = k->tagSizeMeters / 2;
    for (int i = 0; i < 4; i++) {
        double x = signs[i][0] * half, y = signs[i][1] * half;
        double cameraX = r[0] * x + r[1] * y + t[0];
        double cameraY = r[3] * x + r[4] * y + t[1];
        double cameraZ = r[6] * x + r[7] * y + t[2];
        if (!isfinite(cameraZ) || cameraZ <= 1e-9) return 0;
        double du = k->fx * cameraX / cameraZ + k->cx - detection->p[i][0];
        double dv = k->fy * cameraY / cameraZ + k->cy - detection->p[i][1];
        squaredPixels += du * du + dv * dv;
    }
    result->reprojectionRMSEPixels = sqrt(squaredPixels / 4);
    result->rangeMeters = hypot(hypot(t[0], t[1]), t[2]);
    if (!isfinite(result->reprojectionRMSEPixels) || !isfinite(result->rangeMeters) || result->rangeMeters <= 0)
        return 0;
    const double degrees = 180.0 / M_PI;
    result->opticalAxisAngleDegrees = atan2(hypot(t[0], t[1]), t[2]) * degrees;
    double normalLength = hypot(hypot(r[2], r[5]), r[8]);
    double normalRayCosine = fabs((r[2] * t[0] + r[5] * t[1] + r[8] * t[2]) /
                                  (normalLength * result->rangeMeters));
    result->planeAngleDegrees = acos(clamped(normalRayCosine, 0, 1)) * degrees;
    double cosPitch = hypot(r[0], r[3]);
    result->eulerDegrees[1] = atan2(-r[6], cosPitch) * degrees;
    result->eulerSingular = cosPitch < 1e-8;
    if (result->eulerSingular) {
        result->eulerDegrees[0] = 0;
        result->eulerDegrees[2] = atan2(-r[1], r[4]) * degrees;
    } else {
        result->eulerDegrees[0] = atan2(r[7], r[8]) * degrees;
        result->eulerDegrees[2] = atan2(r[3], r[0]) * degrees;
    }
    result->poseError = error;
    result->candidateCount = 1;
    return isfinite(result->planeAngleDegrees) && isfinite(result->opticalAxisAngleDegrees);
}

static void destroyPose(apriltag_pose_t *pose) {
    if (pose->R) matd_destroy(pose->R);
    if (pose->t) matd_destroy(pose->t);
}

static int estimateDetectionPose(apriltag_detection_t *detection,
                                  const AFTagCalibration *k, AFTagPose *result) {
    memset(result, 0, sizeof(*result));
    if (!calibrationValid(k) || !detection || !detection->H || !cornersValid(detection->p))
        return AFTagCoreInvalidInput;
    apriltag_detection_info_t info = {.det = detection, .tagsize = k->tagSizeMeters,
                                     .fx = k->fx, .fy = k->fy, .cx = k->cx, .cy = k->cy};
    apriltag_pose_t candidates[2] = {{0}, {0}};
    double errors[2] = {INFINITY, INFINITY};
    estimate_tag_pose_orthogonal_iteration(&info, &errors[0], &candidates[0], &errors[1], &candidates[1], 50);
    AFTagPose poses[2];
    int valid[2] = {poseCandidate(&candidates[0], errors[0], detection, k, &poses[0]),
                    poseCandidate(&candidates[1], errors[1], detection, k, &poses[1])};
    destroyPose(&candidates[0]); destroyPose(&candidates[1]);
    if (!valid[0] && !valid[1]) return AFTagCorePoseUnavailable;
    int best = !valid[0] ? 1 : (!valid[1] || errors[0] <= errors[1] ? 0 : 1);
    *result = poses[best];
    int other = 1 - best;
    if (valid[other]) {
        result->candidateCount = 2; result->hasSecondPose = 1;
        result->secondPoseError = poses[other].poseError;
        result->secondReprojectionRMSEPixels = poses[other].reprojectionRMSEPixels;
        // Both nearly-zero errors count as equal, without ever emitting 0/0.
        double epsilon = 1e-24 * k->tagSizeMeters * k->tagSizeMeters;
        result->poseErrorRatio = result->secondPoseError <= epsilon ? 1 :
            clamped(result->poseError / result->secondPoseError, 0, 1);
        double traceRelative = 0;
        for (int i = 0; i < 9; i++) traceRelative += result->rotationRowMajor[i] * poses[other].rotationRowMajor[i];
        result->candidateRotationSeparationDegrees = acos(clamped((traceRelative - 1) / 2, -1, 1)) * 180.0 / M_PI;
        double dx = result->translation[0] - poses[other].translation[0];
        double dy = result->translation[1] - poses[other].translation[1];
        double dz = result->translation[2] - poses[other].translation[2];
        result->candidateTranslationSeparationMeters = hypot(hypot(dx, dy), dz);
        result->ambiguous = result->poseErrorRatio >= 0.8 &&
            (result->candidateRotationSeparationDegrees > 1 ||
             result->candidateTranslationSeparationMeters > 0.01 * k->tagSizeMeters);
    }
    return AFTagCoreSuccess;
}

int AFTagCoreEstimatePoseFromCorners(const double corners[4][2],
                                    const AFTagCalibration *calibration, AFTagPose *pose) {
    if (!pose) return AFTagCoreInvalidInput;
    memset(pose, 0, sizeof(*pose));
    if (!calibrationValid(calibration) || !cornersValid(corners)) return AFTagCoreInvalidInput;
    const float ideal[4][2] = {{-1, 1}, {1, 1}, {1, -1}, {-1, -1}};
    zarray_t *correspondences = zarray_create(sizeof(float[4]));
    for (int i = 0; i < 4; i++) {
        float point[4] = {ideal[i][0], ideal[i][1], (float)corners[i][0], (float)corners[i][1]};
        zarray_add(correspondences, point);
    }
    apriltag_detection_t detection = {0};
    memcpy(detection.p, corners, sizeof(detection.p));
    detection.H = homography_compute(correspondences, HOMOGRAPHY_COMPUTE_FLAG_SVD);
    zarray_destroy(correspondences);
    if (!detection.H) return AFTagCorePoseUnavailable;
    int status = estimateDetectionPose(&detection, calibration, pose);
    matd_destroy(detection.H);
    return status;
}

AFTagCore *AFTagCoreCreate(void) {
    AFTagCore *core = calloc(1, sizeof(*core));
    if (!core) return NULL;
    core->family = tag36h11_create();
    core->detector = apriltag_detector_create();
    if (!core->family || !core->detector) { AFTagCoreDestroy(core); return NULL; }
    core->detector->nthreads = 2;
    core->detector->quad_decimate = 2.0f;
    core->detector->refine_edges = true;
    apriltag_detector_add_family_bits(core->detector, core->family, 2);
    return core;
}

void AFTagCoreDestroy(AFTagCore *core) {
    if (!core) return;
    if (core->detector) apriltag_detector_destroy(core->detector);
    if (core->family) tag36h11_destroy(core->family);
    free(core);
}

int AFTagCoreDetect(AFTagCore *core, const uint8_t *gray8, int width, int height,
                    int stride, AFTagDetection **detections, size_t *count) {
    return AFTagCoreDetectCalibrated(core, gray8, width, height, stride, NULL, detections, count);
}

int AFTagCoreDetectCalibrated(AFTagCore *core, const uint8_t *gray8, int width, int height,
                             int stride, const AFTagCalibration *calibration,
                             AFTagDetection **detections, size_t *count) {
    if (detections) *detections = NULL;
    if (count) *count = 0;
    if (!core || !gray8 || !detections || !count || width < 4 || height < 4 || stride < width)
        return AFTagCoreInvalidInput;
    image_u8_t image = { .width = width, .height = height, .stride = stride, .buf = (uint8_t *)gray8 };
    zarray_t *found = apriltag_detector_detect(core->detector, &image);
    if (!found) return AFTagCoreOutOfMemory;
    size_t n = (size_t)zarray_size(found);
    AFTagDetection *output = n ? calloc(n, sizeof(*output)) : NULL;
    if (n && !output) { apriltag_detections_destroy(found); return AFTagCoreOutOfMemory; }
    for (size_t i = 0; i < n; i++) {
        apriltag_detection_t *tag = NULL;
        zarray_get(found, (int)i, &tag);
        output[i].id = tag->id;
        output[i].hamming = tag->hamming;
        output[i].decisionMargin = tag->decision_margin;
        strncpy(output[i].family, "tag36h11", sizeof(output[i].family) - 1);
        memcpy(output[i].center, tag->c, sizeof(output[i].center));
        memcpy(output[i].corners, tag->p, sizeof(output[i].corners));
        if (calibrationValid(calibration))
            output[i].hasPose = estimateDetectionPose(tag, calibration, &output[i].pose) == AFTagCoreSuccess;
    }
    apriltag_detections_destroy(found);
    *detections = output;
    *count = n;
    return AFTagCoreSuccess;
}

void AFTagCoreFreeDetections(AFTagDetection *detections) { free(detections); }
const char *AFTagCoreUpstreamRevision(void) { return "b7c0ebe9aa20f82ec7a828579004f9e706bfecd9"; }
