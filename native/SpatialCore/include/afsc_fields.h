#ifndef AFSC_FIELDS_H
#define AFSC_FIELDS_H
#include "afsc_measurements.h"
#ifdef __cplusplus
extern "C" {
#endif

/* Field geometry is +Z up; AR world remains +Y up. All transforms are
 * column-major T_destination_source; quaternions are [w,x,y,z]. Functions
 * return zero on invalid input and clear output; no NaN missing sentinels. */
AFSCMat4 afsc_field_identity(void);
uint32_t afsc_field_transform_from_pose(AFSCVec3 translation,
    const double quaternion_wxyz[4], AFSCMat4 *output);
uint32_t afsc_field_compose(AFSCMat4 destination_from_middle,
    AFSCMat4 middle_from_source, AFSCMat4 *output);
uint32_t afsc_field_inverse(AFSCMat4 transform, AFSCMat4 *output);
uint32_t afsc_field_transform_point(AFSCMat4 transform, AFSCVec3 point,
    AFSCVec3 *output);
/* Convert WPILib's outward-normal tag frame L to raw detector frame D:
 * (x_L,y_L,z_L)=(-z_D,x_D,-y_D). FTC metadata must declare its own basis. */
uint32_t afsc_field_raw_tag_from_wpilib(AFSCMat4 field_from_layout_tag,
    AFSCMat4 *field_from_detector_tag);
uint32_t afsc_field_observed_tag(AFSCMat4 world_from_arkit_camera,
    AFSCMat4 optical_camera_from_detector_tag, AFSCMat4 *world_from_detector_tag);
/* Unit gravity-up expressed in tag coordinates, and unsigned plane tilt. */
uint32_t afsc_field_gravity(AFSCMat4 frame_from_tag, AFSCVec3 up_in_frame,
    AFSCVec3 *up_in_tag, double *tilt_from_vertical_rad);
/* Caller checks anchor quality first. The resulting rotation maps field +Z
 * exactly onto world +Y. Translation maps the reference tag center to its
 * observed center; residuals must be retained separately rather than hidden. */
uint32_t afsc_field_registration(AFSCMat4 world_from_tag,
    AFSCMat4 field_from_tag, AFSCMat4 *world_from_field);

typedef enum { AFSC_FIELD_UNAVAILABLE = 0, AFSC_FIELD_PASS = 1,
    AFSC_FIELD_FAIL = 2 } AFSCFieldCheckState;
typedef enum { AFSC_ANCHOR_VALID = 0, AFSC_ANCHOR_INVALID_INPUT,
    AFSC_ANCHOR_NOT_FIXED, AFSC_ANCHOR_POSE_UNAVAILABLE,
    AFSC_ANCHOR_SEGMENT_MISMATCH, AFSC_ANCHOR_HEIGHT_UNAVAILABLE,
    AFSC_ANCHOR_HEIGHT_MISMATCH, AFSC_ANCHOR_TILT_MISMATCH,
    AFSC_ANCHOR_GRAVITY_MISMATCH } AFSCAnchorReason;
typedef struct {
    uint32_t fixed_reference, pose_usable, same_segment, floor_datum_available;
    AFSCMat4 field_from_tag, world_from_tag;
    double field_floor_z_m;
    AFSCOptionalDouble observed_height_m; /* Independently selected floor only. */
    double height_tolerance_m, tilt_tolerance_rad, gravity_tolerance_rad;
} AFSCAnchorInput;
typedef struct {
    AFSCFieldCheckState status, height_status, tilt_status, gravity_status;
    AFSCAnchorReason reason;
    AFSCOptionalDouble expected_height_m, observed_height_m, height_difference_m;
    AFSCOptionalDouble expected_tilt_rad, observed_tilt_rad, tilt_difference_rad;
    AFSCOptionalDouble gravity_difference_rad;
} AFSCAnchorCheck;
AFSCAnchorCheck afsc_field_check_anchor(const AFSCAnchorInput *input);

typedef struct { double edge_m, relative_tolerance; } AFSCSizeStandard;
typedef enum { AFSC_SIZE_SELECTED = 0, AFSC_SIZE_INVALID_INPUT,
    AFSC_SIZE_TRACKING_UNAVAILABLE, AFSC_SIZE_DEPTH_UNAVAILABLE,
    AFSC_SIZE_POSE_UNAVAILABLE, AFSC_SIZE_NO_UNIQUE_MATCH,
    AFSC_SIZE_TOO_FAR } AFSCSizeReason;
typedef struct {
    uint32_t automatic, tracking_usable;
    double reference_edge_m;
    AFSCOptionalDouble selected_edge_m; /* Explicit preset/package/custom edge. */
    AFSCPoseObservation pose;
    AFSCDepthObservation depth;
    AFSCMeasurementSettings settings;
    const AFSCSizeStandard *standards; /* Optional; defaults match current app. */
    size_t standard_count;
} AFSCSizeInput;
typedef struct {
    uint32_t selected;
    AFSCSizeReason reason;
    AFSCOptionalDouble edge_m, estimated_edge_m, relative_tolerance, scale;
    int32_t standard_index; /* -1 for explicit/unresolved. */
} AFSCSizeResolution;
AFSCSizeResolution afsc_field_resolve_size(const AFSCSizeInput *input);
typedef struct {
    AFSCVec3 translation;
    double reference_edge_m;
    AFSCOptionalDouble pose_error_m2, second_pose_error_m2,
        candidate_translation_separation_m;
} AFSCMetricPose;
typedef struct {
    uint32_t available;
    AFSCVec3 translation;
    double edge_m, range_m;
    AFSCOptionalDouble pose_error_m2, second_pose_error_m2,
        candidate_translation_separation_m;
} AFSCRescaledMetricPose;
AFSCRescaledMetricPose afsc_field_rescale_metric_pose(
    const AFSCMetricPose *pose, double selected_edge_m);

/* One walk = one pinned field package; package identity stays in the adapter.
 * Strings are copied, bounded to 256 bytes (family 31). Observation identity
 * is (segment, frame, family, ID), so UI rereads never inflate counts. */
typedef struct AFSCFieldWalk AFSCFieldWalk;
typedef enum { AFSC_WALK_INVALID = 0, AFSC_WALK_ADDED = 1,
    AFSC_WALK_DUPLICATE = 2, AFSC_WALK_CAPACITY = 3 } AFSCWalkResult;
typedef struct {
    const char *family; /* Borrowed until next mutation/destruction of this walk. */
    int32_t tag_id;
    uint64_t observation_count, accepted_count, rejected_count;
    double first_seen_s, last_seen_s;
} AFSCFieldWalkRow;
AFSCFieldWalk *afsc_field_walk_create(size_t maximum_rows,
    size_t maximum_observations);
void afsc_field_walk_destroy(AFSCFieldWalk *walk);
void afsc_field_walk_clear(AFSCFieldWalk *walk);
AFSCWalkResult afsc_field_walk_observe(AFSCFieldWalk *walk,
    AFSCStringView family, int32_t tag_id, AFSCStringView segment_id,
    AFSCStringView frame_id, double timestamp_s, uint32_t accepted);
size_t afsc_field_walk_count(const AFSCFieldWalk *walk);
uint32_t afsc_field_walk_row(const AFSCFieldWalk *walk, size_t index,
    AFSCFieldWalkRow *output);
#ifdef __cplusplus
}
#endif
#endif
