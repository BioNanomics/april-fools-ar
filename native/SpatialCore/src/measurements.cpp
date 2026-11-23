#include "afsc_measurements.h"
#include <cmath>

namespace {
bool isFinite(double x) { return std::isfinite(x); }
bool isFinite(AFSCVec2 v) { return isFinite(v.x) && isFinite(v.y); }
bool isFinite(AFSCVec3 v) { return isFinite(v.x) && isFinite(v.y) && isFinite(v.z); }
bool present(AFSCOptionalDouble x) { return x.available && isFinite(x.value); }
AFSCOptionalDouble some(double value) { return {1, value}; }
AFSCOptionalDouble acceptedDepth(const AFSCDepthObservation *d) {
    return d && present(d->center_z_m) && d->center_z_m.value > 0 && present(d->confidence)
        && (d->confidence.value == 1 || d->confidence.value == 2) ? d->center_z_m : AFSCOptionalDouble{};
}
bool validIntrinsics(const AFSCIntrinsics *k) {
    if (!k) return false;
    for (double value : k->values) if (!isFinite(value)) return false;
    return k->values[0] > 0 && k->values[4] > 0;
}
AFSCVec3 unproject(AFSCVec2 center, double z, const AFSCIntrinsics &k) {
    return {(center.x-k.values[6])/k.values[0]*z, (center.y-k.values[7])/k.values[4]*z, z};
}
AFSCOptionalDouble range(AFSCVec3 p) {
    if (!isFinite(p)) return {};
    const double value = std::hypot(std::hypot(p.x, p.y), p.z);
    return isFinite(value) && value > 0 ? some(value) : AFSCOptionalDouble{};
}
bool settingsValid(const AFSCMeasurementSettings *s) {
    return s && isFinite(s->max_range_m) && s->max_range_m > 0
        && isFinite(s->max_plane_angle_rad) && s->max_plane_angle_rad > 0
        && isFinite(s->max_reprojection_rms_px) && s->max_reprojection_rms_px > 0
        && isFinite(s->warning_depth_difference_m) && s->warning_depth_difference_m >= 0
        && isFinite(s->reject_depth_difference_m) && s->reject_depth_difference_m > s->warning_depth_difference_m;
}
bool rigidTransform(const AFSCMat4 &m) {
    for (double value : m.values) if (!isFinite(value)) return false;
    if (std::abs(m.values[3]) >= 1e-4 || std::abs(m.values[7]) >= 1e-4
        || std::abs(m.values[11]) >= 1e-4 || std::abs(m.values[15]-1) >= 1e-4) return false;
    for (int a = 0; a < 3; ++a) for (int b = 0; b < 3; ++b) {
        double dot = 0;
        for (int row = 0; row < 3; ++row) dot += m.values[a*4+row]*m.values[b*4+row];
        if (std::abs(dot-(a == b ? 1.0 : 0.0)) >= 1e-3) return false;
    }
    const double *v = m.values;
    const double determinant = v[0]*(v[5]*v[10]-v[9]*v[6])
        - v[4]*(v[1]*v[10]-v[9]*v[2]) + v[8]*(v[1]*v[6]-v[5]*v[2]);
    return std::abs(determinant-1) < 1e-3;
}
}

extern "C" AFSCCameraRanges afsc_camera_ranges(const AFSCPoseObservation *pose,
    const AFSCDepthObservation *depth, const AFSCIntrinsics *intrinsics,
    uint32_t center_available, AFSCVec2 center_px) {
    AFSCCameraRanges out{};
    out.depth_reason = AFSC_RANGE_MISSING_DEPTH;
    out.pose_reason = AFSC_RANGE_POSE_UNAVAILABLE;
    if (pose && pose->translation_available && isFinite(pose->translation) && pose->translation.z > 0) {
        out.pose_z_m = some(pose->translation.z);
        out.pose_range_m = range(pose->translation);
        out.pose_reason = out.pose_range_m.available ? AFSC_RANGE_VALID : AFSC_RANGE_INVALID_RANGE;
    }
    if (!depth || !present(depth->center_z_m) || depth->center_z_m.value <= 0) return out;
    const auto z = acceptedDepth(depth);
    if (!z.available) { out.depth_reason = AFSC_RANGE_INVALID_CONFIDENCE; return out; }
    out.depth_z_m = z;
    if (!validIntrinsics(intrinsics)) { out.depth_reason = AFSC_RANGE_INVALID_INTRINSICS; return out; }
    if (!center_available || !isFinite(center_px) || center_px.x < 0 || center_px.y < 0) {
        out.depth_reason = AFSC_RANGE_INVALID_CENTER; return out;
    }
    out.depth_range_m = range(unproject(center_px, z.value, *intrinsics));
    out.depth_reason = out.depth_range_m.available ? AFSC_RANGE_VALID : AFSC_RANGE_INVALID_RANGE;
    if (out.depth_range_m.available && out.pose_range_m.available) {
        const double delta = std::abs(out.depth_range_m.value-out.pose_range_m.value);
        if (isFinite(delta)) out.range_difference_m = some(delta);
    }
    return out;
}

extern "C" AFSCPoseQuality afsc_pose_quality(const AFSCPoseObservation *p,
    const AFSCDepthObservation *d, const AFSCMeasurementSettings *s, uint32_t tracking_usable) {
    AFSCPoseQuality out{};
    out.accepted_depth_z_m = acceptedDepth(d);
    if (p && p->translation_available && isFinite(p->translation) && out.accepted_depth_z_m.available) {
        const double delta = std::abs(out.accepted_depth_z_m.value-p->translation.z);
        if (isFinite(delta)) out.depth_difference_m = some(delta);
    }
    auto fail = [&](AFSCQualityReason reason, AFSCSeverity severity) {
        out.reason = reason; out.severity = severity; return out;
    };
    if (!tracking_usable) return fail(AFSC_QUALITY_TRACKING_LIMITED, AFSC_SEVERITY_NEUTRAL);
    if (!p || !p->translation_available || !isFinite(p->translation) || p->translation.z <= 0
        || !p->orientation_available || !present(p->range_m) || !present(p->plane_angle_rad)
        || !present(p->bearing_rad) || !present(p->reprojection_rms_px) || !settingsValid(s))
        return fail(AFSC_QUALITY_POSE_UNAVAILABLE, AFSC_SEVERITY_NEUTRAL);
    if (p->ambiguous == 1) return fail(AFSC_QUALITY_AMBIGUOUS, AFSC_SEVERITY_WARNING);
    if (p->range_m.value > s->max_range_m) return fail(AFSC_QUALITY_TOO_FAR, AFSC_SEVERITY_BAD);
    if (p->plane_angle_rad.value > s->max_plane_angle_rad) return fail(AFSC_QUALITY_BAD_ANGLE, AFSC_SEVERITY_BAD);
    if (p->reprojection_rms_px.value > s->max_reprojection_rms_px || !present(p->corrected_bits)
        || p->corrected_bits.value > 0 || !present(p->decision_margin) || p->decision_margin.value <= 0)
        return fail(AFSC_QUALITY_LOW_CONFIDENCE_POSE, AFSC_SEVERITY_WARNING);
    if (d && present(d->confidence) && d->confidence.value == 0)
        return fail(AFSC_QUALITY_LOW_CONFIDENCE_DEPTH, AFSC_SEVERITY_NEUTRAL);
    if (!out.accepted_depth_z_m.available) return fail(AFSC_QUALITY_MISSING_DEPTH, AFSC_SEVERITY_NEUTRAL);
    if (out.depth_difference_m.value > s->reject_depth_difference_m+1e-9)
        return fail(AFSC_QUALITY_DEPTH_REJECTED, AFSC_SEVERITY_BAD);
    if (out.depth_difference_m.value > s->warning_depth_difference_m+1e-9)
        return fail(AFSC_QUALITY_DEPTH_WARNING, AFSC_SEVERITY_WARNING);
    return fail(AFSC_QUALITY_VALID, AFSC_SEVERITY_GOOD);
}

extern "C" AFSCFloorHeight afsc_floor_height(const AFSCFloorHeightInput *i) {
    AFSCFloorHeight out{};
    auto fail = [&](AFSCHeightReason reason) { out.reason = reason; return out; };
    if (!i || !i->floor_available) return fail(AFSC_HEIGHT_FLOOR_NOT_SELECTED);
    if (!i->same_segment) return fail(AFSC_HEIGHT_SEGMENT_MISMATCH);
    if (!i->tracking_usable) return fail(AFSC_HEIGHT_TRACKING_LIMITED);
    if (!isFinite(i->timestamp_s) || !isFinite(i->frame_age_s) || i->frame_age_s < 0
        || i->frame_age_s > 0.4 || !i->frame_id_available) return fail(AFSC_HEIGHT_STALE_FRAME);
    if (!i->floor_id_available || !i->floor_frame_id_available || !isFinite(i->floor_timestamp_s)
        || !isFinite(i->floor.origin) || !isFinite(i->floor.normal) || !i->floor_classification_usable)
        return fail(AFSC_HEIGHT_INVALID_FLOOR);
    const auto &p = i->pose;
    const auto &s = i->settings;
    if (!rigidTransform(i->world_from_optical) || !validIntrinsics(&i->intrinsics) || !settingsValid(&s)
        || !p.translation_available || !isFinite(p.translation) || p.translation.z <= 0
        || !present(p.range_m) || p.range_m.value <= 0 || !present(p.plane_angle_rad) || p.plane_angle_rad.value < 0
        || !present(p.reprojection_rms_px) || p.reprojection_rms_px.value < 0)
        return fail(AFSC_HEIGHT_INVALID_POSE);
    if (p.ambiguous != 0) return fail(AFSC_HEIGHT_AMBIGUOUS_POSE);
    if (p.range_m.value > s.max_range_m) return fail(AFSC_HEIGHT_TOO_FAR);
    if (p.plane_angle_rad.value > s.max_plane_angle_rad) return fail(AFSC_HEIGHT_BAD_ANGLE);
    if (p.reprojection_rms_px.value > s.max_reprojection_rms_px || !present(p.corrected_bits)
        || p.corrected_bits.value != 0 || !present(p.decision_margin) || p.decision_margin.value <= 0)
        return fail(AFSC_HEIGHT_LOW_CONFIDENCE_POSE);
    const auto depth = acceptedDepth(&i->depth);
    out.accepted_depth_z_m = depth;
    if (depth.available) {
        const double delta = std::abs(depth.value-p.translation.z);
        if (!isFinite(delta)) return fail(AFSC_HEIGHT_INVALID_GEOMETRY);
        out.depth_difference_m = some(delta);
        if (delta > s.reject_depth_difference_m+1e-9) return fail(AFSC_HEIGHT_DEPTH_MISMATCH);
        if (!i->center_available || !isFinite(i->center_px) || i->center_px.x < 0 || i->center_px.y < 0)
            return fail(AFSC_HEIGHT_INVALID_CENTER);
        out.optical_m = unproject(i->center_px, depth.value, i->intrinsics);
        out.source = AFSC_HEIGHT_SOURCE_DEPTH;
    } else { out.optical_m = p.translation; out.source = AFSC_HEIGHT_SOURCE_POSE; }
    if (!isFinite(out.optical_m)) return fail(AFSC_HEIGHT_INVALID_GEOMETRY);
    const double *m = i->world_from_optical.values;
    const auto optical = out.optical_m;
    out.world_m = {m[0]*optical.x+m[4]*optical.y+m[8]*optical.z+m[12],
                   m[1]*optical.x+m[5]*optical.y+m[9]*optical.z+m[13],
                   m[2]*optical.x+m[6]*optical.y+m[10]*optical.z+m[14]};
    const double w = m[3]*optical.x+m[7]*optical.y+m[11]*optical.z+m[15];
    if (!isFinite(out.world_m) || !isFinite(w) || std::abs(w-1) >= 1e-3) return fail(AFSC_HEIGHT_INVALID_GEOMETRY);
    const auto n = i->floor.normal;
    const auto o = i->floor.origin;
    const double norm = std::hypot(std::hypot(n.x, n.y), n.z);
    if (!isFinite(norm) || norm <= 0 || std::abs(n.y)/norm < 0.8) return fail(AFSC_HEIGHT_INVALID_INTERSECTION);
    out.height_m = (n.x*(out.world_m.x-o.x)+n.y*(out.world_m.y-o.y)+n.z*(out.world_m.z-o.z))/n.y;
    out.floor_foot_world_m = {out.world_m.x, out.world_m.y-out.height_m, out.world_m.z};
    if (!isFinite(out.height_m) || out.height_m < 0 || out.height_m > 30 || !isFinite(out.floor_foot_world_m))
        return fail(AFSC_HEIGHT_INVALID_INTERSECTION);
    out.available = 1;
    out.reason = AFSC_HEIGHT_VALID;
    out.severity = out.source == AFSC_HEIGHT_SOURCE_POSE
        || (out.depth_difference_m.available && out.depth_difference_m.value > s.warning_depth_difference_m+1e-9)
        ? AFSC_SEVERITY_WARNING : AFSC_SEVERITY_GOOD;
    return out;
}

extern "C" AFSCGravityOrientation afsc_gravity_orientation(const AFSCGravityOrientationInput *i) {
    AFSCGravityOrientation out{};
    auto fail = [&](AFSCGravityOrientationReason reason) { out.reason = reason; return out; };
    if (!i) return fail(AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    if (!i->tracking_usable) return fail(AFSC_GRAVITY_ORIENTATION_TRACKING_LIMITED);
    if (!i->frame_id_available || !isFinite(i->timestamp_s) || !isFinite(i->frame_age_s)
        || i->frame_age_s < 0 || i->frame_age_s > 0.4)
        return fail(AFSC_GRAVITY_ORIENTATION_STALE_FRAME);
    const auto &p = i->pose;
    const auto &s = i->settings;
    const double halfPi = std::acos(-1.0)/2;
    const auto measuredRange = p.translation_available ? range(p.translation) : AFSCOptionalDouble{};
    const auto &tag = i->optical_from_tag_rotation;
    if (!rigidTransform(i->world_from_optical) || !rigidTransform(tag)
        || std::abs(tag.values[12]) > 1e-8 || std::abs(tag.values[13]) > 1e-8 || std::abs(tag.values[14]) > 1e-8
        || !isFinite(s.max_range_m) || s.max_range_m <= 0
        || !isFinite(s.max_plane_angle_rad) || s.max_plane_angle_rad <= 0 || s.max_plane_angle_rad > halfPi
        || !isFinite(s.max_reprojection_rms_px) || s.max_reprojection_rms_px <= 0
        || !p.orientation_available || !measuredRange.available || p.translation.z <= 0
        || !present(p.range_m) || p.range_m.value <= 0
        || !present(p.plane_angle_rad) || p.plane_angle_rad.value < 0 || p.plane_angle_rad.value > halfPi
        || !present(p.reprojection_rms_px) || p.reprojection_rms_px.value < 0)
        return fail(AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    if (p.ambiguous != 0) return fail(AFSC_GRAVITY_ORIENTATION_AMBIGUOUS_POSE);
    if (measuredRange.value > s.max_range_m || p.range_m.value > s.max_range_m)
        return fail(AFSC_GRAVITY_ORIENTATION_TOO_FAR);
    if (p.plane_angle_rad.value > s.max_plane_angle_rad)
        return fail(AFSC_GRAVITY_ORIENTATION_BAD_ANGLE);
    if (p.reprojection_rms_px.value > s.max_reprojection_rms_px || !present(p.corrected_bits)
        || p.corrected_bits.value != 0 || !present(p.decision_margin) || p.decision_margin.value <= 0)
        return fail(AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE);
    const double *camera = i->world_from_optical.values;
    for (int column = 0; column < 3; ++column) for (int row = 0; row < 3; ++row) {
        double value = 0;
        for (int k = 0; k < 3; ++k) value += camera[k*4+row]*tag.values[column*4+k];
        out.world_from_tag_rotation.values[column*4+row] = value;
    }
    out.world_from_tag_rotation.values[15] = 1;
    const double *r = out.world_from_tag_rotation.values;
    const auto unit = [](AFSCVec3 v) {
        const double length = std::hypot(std::hypot(v.x, v.y), v.z);
        return AFSCVec3{v.x/length, v.y/length, v.z/length};
    };
    const auto right = unit({r[0], r[1], r[2]});
    out.up_world = unit({-r[4], -r[5], -r[6]});
    out.normal_world = unit({r[8], r[9], r[10]});
    // Rounding in otherwise valid rotations can place |normal.y| slightly over 1.
    out.tilt_from_vertical_rad = std::asin(std::fmin(1.0, std::abs(out.normal_world.y)));
    if (std::hypot(right.y, out.up_world.y) > 1e-4)
        out.twist_rad = some(std::atan2(-right.y, out.up_world.y));
    out.available = 1;
    out.reason = AFSC_GRAVITY_ORIENTATION_VALID;
    return out;
}

extern "C" uint32_t afsc_measured_tag_size(uint32_t point_count, uint32_t tracking_usable,
    uint32_t points_usable, double frame_age_s, AFSCOptionalDouble distance_m) {
    return point_count == 2 && tracking_usable && points_usable && isFinite(frame_age_s)
        && frame_age_s >= 0 && frame_age_s <= 0.5 && present(distance_m)
        && distance_m.value >= 0.01 && distance_m.value <= 2;
}
