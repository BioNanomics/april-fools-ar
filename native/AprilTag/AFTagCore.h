#ifndef AF_TAG_CORE_H
#define AF_TAG_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AFTagCore AFTagCore;
typedef struct {
    double fx, fy, cx, cy; // Original image pixels, zero-skew pinhole model.
    double tagSizeMeters; // Edge between detection corners; excludes outer paper margin.
} AFTagCalibration;

typedef struct {
    double translation[3]; // Tag center in camera optical x-right/y-down/z-forward, meters.
    double rotationRowMajor[9]; // p_camera = R * p_tag + translation.
    double eulerDegrees[3]; // Legacy optical Rot X/Y/Z, R=Rz(RotZ) Ry(RotY) Rx(RotX); not FTC/FRC angles.
    double rangeMeters; // Legacy ABI name: Euclidean 3-D camera-to-tag-center distance.
    double opticalAxisAngleDegrees; // Unsigned optical-axis offset, not FTC horizontal bearing.
    double planeAngleDegrees; // Legacy ABI name: viewing incidence acos(abs(normal dot center ray)); 0=head-on.
    double reprojectionRMSEPixels; // sqrt(sum of four squared 2D corner distances / 4).
    double poseError; // Upstream object-space sum of squared distances to rays, m^2; NOT pixels.
    int candidateCount; // Numerically valid, positive-depth solutions (one or two).
    int hasSecondPose;
    double secondPoseError;
    double secondReprojectionRMSEPixels;
    double poseErrorRatio; // best/second in [0,1], available only if hasSecondPose.
    double candidateRotationSeparationDegrees;
    double candidateTranslationSeparationMeters;
    int ambiguous; // Ratio >=0.8 AND rotation >1deg or translation >1% tag edge.
    int eulerSingular; // At optical Rot Y +/-90deg, Rot X=0; matrix is authoritative.
} AFTagPose;

typedef struct {
    int id;
    char family[16];
    int hamming;
    double decisionMargin;
    double center[2];
    double corners[4][2];
    int hasPose;
    AFTagPose pose;
} AFTagDetection;

enum { AFTagCoreSuccess = 0, AFTagCoreInvalidInput = 1, AFTagCoreOutOfMemory = 2,
       AFTagCorePoseUnavailable = 3 };

/// Reuse one instance serially. Default family tag36h11, 2 threads, decimation 2.
AFTagCore *AFTagCoreCreate(void);
void AFTagCoreDestroy(AFTagCore *core);
/// Input is borrowed for this call only. Output coordinates remain in the
/// original grayscale image pixels despite internal quad decimation.
/// On success, free *detections with AFTagCoreFreeDetections (NULL is allowed).
int AFTagCoreDetect(AFTagCore *core, const uint8_t *gray8, int width, int height,
                    int stride, AFTagDetection **detections, size_t *count);
/// Missing/invalid calibration preserves detections but leaves hasPose=0.
int AFTagCoreDetectCalibrated(AFTagCore *core, const uint8_t *gray8, int width, int height,
                             int stride, const AFTagCalibration *calibration,
                             AFTagDetection **detections, size_t *count);
/// Solve ordered upstream detection corners directly, for shared geometry use/tests.
/// Invalid calibration/corners return nonzero and zero the output; no fake pose.
int AFTagCoreEstimatePoseFromCorners(const double corners[4][2],
                                    const AFTagCalibration *calibration, AFTagPose *pose);
void AFTagCoreFreeDetections(AFTagDetection *detections);
const char *AFTagCoreUpstreamRevision(void);

#ifdef __cplusplus
}
#endif
#endif
