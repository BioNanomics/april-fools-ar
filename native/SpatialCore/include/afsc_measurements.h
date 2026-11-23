#ifndef AFSC_MEASUREMENTS_H
#define AFSC_MEASUREMENTS_H
#include "afsc_types.h"
#ifdef __cplusplus
extern "C" {
#endif
/* Optional values never use zero as a missing sentinel. Angles are radians.
 * A sensor adapter decides whether tracking is usable; the core knows no ARKit states.
 * Pose and depth must describe the same captured frame and calibration. Callers retain
 * frame/segment/clock metadata in their records; floor checks below enforce its validity.
 */
typedef struct { uint32_t available; double value; } AFSCOptionalDouble;
typedef struct {
    uint32_t translation_available;
    AFSCVec3 translation;
    uint32_t orientation_available;
    AFSCOptionalDouble range_m, plane_angle_rad, bearing_rad, reprojection_rms_px;
    AFSCOptionalDouble decision_margin, corrected_bits;
    int32_t ambiguous; /* -1 unknown, 0 resolved, 1 ambiguous */
} AFSCPoseObservation;
typedef struct {
    AFSCOptionalDouble center_z_m;
    AFSCOptionalDouble confidence; /* accepted categories exactly 1 or 2, not covariance */
} AFSCDepthObservation;
typedef struct {
    double max_range_m, max_plane_angle_rad, max_reprojection_rms_px;
    double warning_depth_difference_m, reject_depth_difference_m;
} AFSCMeasurementSettings;

typedef enum {
    AFSC_RANGE_VALID = 0, AFSC_RANGE_MISSING_DEPTH, AFSC_RANGE_POSE_UNAVAILABLE,
    AFSC_RANGE_INVALID_CONFIDENCE, AFSC_RANGE_INVALID_INTRINSICS,
    AFSC_RANGE_INVALID_CENTER, AFSC_RANGE_INVALID_RANGE
} AFSCRangeReason;
typedef struct {
    AFSCOptionalDouble depth_range_m, pose_range_m, range_difference_m;
    AFSCOptionalDouble depth_z_m, pose_z_m;
    AFSCRangeReason depth_reason, pose_reason;
} AFSCCameraRanges;
/* Independent diagnostics: pose norm is recomputed from translation, never cached.
 * Euclidean range difference and axial Z difference are intentionally distinct. */
AFSCCameraRanges afsc_camera_ranges(const AFSCPoseObservation *pose,
    const AFSCDepthObservation *depth, const AFSCIntrinsics *intrinsics,
    uint32_t center_available, AFSCVec2 center_px);

typedef enum {
    AFSC_QUALITY_VALID = 0, AFSC_QUALITY_TRACKING_LIMITED, AFSC_QUALITY_POSE_UNAVAILABLE,
    AFSC_QUALITY_AMBIGUOUS, AFSC_QUALITY_TOO_FAR, AFSC_QUALITY_BAD_ANGLE,
    AFSC_QUALITY_LOW_CONFIDENCE_POSE, AFSC_QUALITY_LOW_CONFIDENCE_DEPTH,
    AFSC_QUALITY_MISSING_DEPTH, AFSC_QUALITY_DEPTH_REJECTED, AFSC_QUALITY_DEPTH_WARNING
} AFSCQualityReason;
typedef enum { AFSC_SEVERITY_GOOD = 0, AFSC_SEVERITY_NEUTRAL, AFSC_SEVERITY_WARNING, AFSC_SEVERITY_BAD } AFSCSeverity;
typedef struct {
    AFSCQualityReason reason;
    AFSCSeverity severity;
    AFSCOptionalDouble accepted_depth_z_m, depth_difference_m;
} AFSCPoseQuality;
AFSCPoseQuality afsc_pose_quality(const AFSCPoseObservation *pose,
    const AFSCDepthObservation *depth, const AFSCMeasurementSettings *settings,
    uint32_t tracking_usable);

typedef enum {
    AFSC_HEIGHT_VALID = 0, AFSC_HEIGHT_FLOOR_NOT_SELECTED, AFSC_HEIGHT_SEGMENT_MISMATCH,
    AFSC_HEIGHT_TRACKING_LIMITED, AFSC_HEIGHT_STALE_FRAME, AFSC_HEIGHT_INVALID_FLOOR,
    AFSC_HEIGHT_INVALID_POSE, AFSC_HEIGHT_AMBIGUOUS_POSE, AFSC_HEIGHT_TOO_FAR,
    AFSC_HEIGHT_BAD_ANGLE, AFSC_HEIGHT_LOW_CONFIDENCE_POSE, AFSC_HEIGHT_DEPTH_MISMATCH,
    AFSC_HEIGHT_INVALID_CENTER, AFSC_HEIGHT_INVALID_GEOMETRY, AFSC_HEIGHT_INVALID_INTERSECTION
} AFSCHeightReason;
typedef enum { AFSC_HEIGHT_SOURCE_NONE = 0, AFSC_HEIGHT_SOURCE_DEPTH, AFSC_HEIGHT_SOURCE_POSE } AFSCHeightSource;
typedef struct {
    uint32_t floor_available, same_segment, tracking_usable, frame_id_available;
    uint32_t floor_id_available, floor_frame_id_available, floor_classification_usable;
    double timestamp_s, frame_age_s, floor_timestamp_s;
    AFSCPlane floor;
    /* Rigid T_world_optical: adapters convert their native camera axes once. */
    AFSCMat4 world_from_optical;
    AFSCIntrinsics intrinsics;
    uint32_t center_available;
    AFSCVec2 center_px;
    AFSCPoseObservation pose;
    AFSCDepthObservation depth;
    AFSCMeasurementSettings settings;
} AFSCFloorHeightInput;
typedef struct {
    uint32_t available;
    AFSCHeightReason reason;
    AFSCHeightSource source;
    AFSCSeverity severity;
    double height_m;
    AFSCVec3 optical_m, world_m, floor_foot_world_m;
    AFSCOptionalDouble accepted_depth_z_m, depth_difference_m;
} AFSCFloorHeight;
/* Uses accepted center depth, otherwise a qualified pose fallback. A known depth
 * mismatch blocks both sources. Height is gravity-vertical, not normal distance.
 * The current conservative policy requires <=0.4 s frame age, floor |normal.y| /
 * |normal| >=0.8, and a nonnegative height <=30 m. */
AFSCFloorHeight afsc_floor_height(const AFSCFloorHeightInput *input);

typedef enum {
    AFSC_GRAVITY_ORIENTATION_VALID = 0, AFSC_GRAVITY_ORIENTATION_TRACKING_LIMITED,
    AFSC_GRAVITY_ORIENTATION_STALE_FRAME, AFSC_GRAVITY_ORIENTATION_INVALID_POSE,
    AFSC_GRAVITY_ORIENTATION_AMBIGUOUS_POSE, AFSC_GRAVITY_ORIENTATION_TOO_FAR,
    AFSC_GRAVITY_ORIENTATION_BAD_ANGLE, AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE
} AFSCGravityOrientationReason;
typedef struct {
    uint32_t tracking_usable, frame_id_available;
    double timestamp_s, frame_age_s;
    /* Both rotations describe the same captured frame. World is gravity +Y up.
     * The camera transform is rigid; the tag matrix is a homogeneous pure rotation
     * with zero translation. Adapters convert native camera axes exactly once. */
    AFSCMat4 world_from_optical, optical_from_tag_rotation;
    AFSCPoseObservation pose;
    AFSCMeasurementSettings settings;
} AFSCGravityOrientationInput;
typedef struct {
    uint32_t available;
    AFSCGravityOrientationReason reason;
    AFSCMat4 world_from_tag_rotation;
    AFSCVec3 normal_world, up_world; /* Unit +tag Z (into print), -tag Y (printed up). */
    double tilt_from_vertical_rad; /* [0, pi/2]: 0 vertical plane, pi/2 horizontal. */
    AFSCOptionalDouble twist_rad; /* [-pi, pi]: clockwise from printed front. */
} AFSCGravityOrientation;
/* Compose world-from-optical and optical-from-tag rotations, without Euler-angle
 * addition. No floor, depth, image intrinsics or heading reference is required.
 * Requires a resolved pose and <=0.4 s frame age; only the range, incidence and
 * reprojection settings apply. Twist is relative to gravity projected into the
 * tag plane, and unavailable when that projection's magnitude is <=1e-4. */
AFSCGravityOrientation afsc_gravity_orientation(const AFSCGravityOrientationInput *input);

/* Numeric validation for an operator-reviewed two-point tag edge. Sensor/source
 * and segment identity are supplied by the native adapter, never guessed. */
uint32_t afsc_measured_tag_size(uint32_t point_count, uint32_t tracking_usable,
    uint32_t points_usable, double frame_age_s, AFSCOptionalDouble distance_m);
#ifdef __cplusplus
}
#endif
#endif
