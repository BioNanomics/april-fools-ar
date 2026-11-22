#include "afsc_measurements.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>

namespace {
constexpr double pi = 3.14159265358979323846;
AFSCOptionalDouble value(double x) { return {1, x}; }
void near(double actual, double expected, double tolerance = 1e-10) { assert(std::abs(actual-expected) <= tolerance); }
AFSCMeasurementSettings settings() { return {10, pi/3, 3, 0.10, 0.15}; }
AFSCPoseObservation pose() {
    AFSCPoseObservation p{};
    p.translation_available = 1; p.translation = {0.21, 0.21, 2.1}; p.orientation_available = 1;
    p.range_m = value(2.1209); p.plane_angle_rad = value(8*pi/180); p.bearing_rad = value(8*pi/180);
    p.reprojection_rms_px = value(0.5); p.decision_margin = value(80); p.corrected_bits = value(0);
    return p;
}
AFSCFloorHeightInput heightInput() {
    AFSCFloorHeightInput i{};
    i.floor_available = i.same_segment = i.tracking_usable = i.frame_id_available = 1;
    i.floor_id_available = i.floor_frame_id_available = i.floor_classification_usable = 1;
    i.timestamp_s = 100; i.frame_age_s = 0.1; i.floor_timestamp_s = 90;
    i.floor = {{0, 0, 0}, {0, 1, 0}};
    // Native camera rotated 90 degrees around Z, then optical +Y/+Z axis conversion.
    i.world_from_optical = {{0, 1, 0, 0, 1, 0, 0, 0, 0, 0, -1, 0, 1, 2, 3, 1}};
    i.intrinsics = {{400, 0, 0, 0, 600, 0, 160, 120, 1}};
    i.center_available = 1; i.center_px = {200, 180};
    i.pose = pose(); i.depth = {value(2), value(2)}; i.settings = settings();
    return i;
}
void ranges() {
    auto p = pose(); p.translation = {3, 4, 5}; p.range_m = value(999);
    AFSCIntrinsics k{{100, 0, 0, 0, 200, 0, 50, 80, 1}};
    AFSCDepthObservation d{value(5), value(2)};
    auto r = afsc_camera_ranges(&p, &d, &k, 1, {110, 240});
    near(r.depth_range_m.value, std::sqrt(50)); near(r.pose_range_m.value, std::sqrt(50));
    assert(r.range_difference_m.available); near(r.range_difference_m.value, 0);
    near(r.depth_z_m.value, 5); near(r.pose_z_m.value, 5);
    p.translation = {0, 0, 5}; r = afsc_camera_ranges(&p, &d, &k, 1, {110, 240});
    near(r.range_difference_m.value, std::sqrt(50)-5);
    for (double confidence : {0., 3., 1.5, std::numeric_limits<double>::quiet_NaN()}) {
        d.confidence = value(confidence); r = afsc_camera_ranges(&p, &d, &k, 1, {110, 240});
        assert(!r.depth_range_m.available && !r.depth_z_m.available);
        assert(r.pose_range_m.available && r.depth_reason == AFSC_RANGE_INVALID_CONFIDENCE);
    }
    d.confidence = value(1); k.values[0] = 0;
    r = afsc_camera_ranges(&p, &d, &k, 1, {110, 240});
    assert(r.depth_reason == AFSC_RANGE_INVALID_INTRINSICS && r.depth_z_m.available);
    k.values[0] = 100;
    r = afsc_camera_ranges(&p, &d, &k, 0, {});
    assert(r.depth_reason == AFSC_RANGE_INVALID_CENTER && r.depth_z_m.available);
    p.translation.z = -1;
    r = afsc_camera_ranges(&p, &d, &k, 1, {110, 240});
    assert(!r.pose_range_m.available && r.depth_range_m.available);
    r = afsc_camera_ranges(nullptr, nullptr, nullptr, 0, {});
    assert(!r.pose_range_m.available && !r.depth_range_m.available);
    p.translation = {1e308, 1e308, 1e308};
    r = afsc_camera_ranges(&p, nullptr, nullptr, 0, {});
    assert(r.pose_range_m.available); // hypot avoids intermediate squared overflow.
    p.translation = {1.7e308, 1.7e308, 1.7e308};
    r = afsc_camera_ranges(&p, nullptr, nullptr, 0, {});
    assert(!r.pose_range_m.available && r.pose_reason == AFSC_RANGE_INVALID_RANGE);
}
void quality() {
    auto p = pose(); auto s = settings(); AFSCDepthObservation d{value(2.1), value(2)};
    auto q = afsc_pose_quality(&p, &d, &s, 1); assert(q.reason == AFSC_QUALITY_VALID);
    d.center_z_m = value(2.2); q = afsc_pose_quality(&p, &d, &s, 1); assert(q.reason == AFSC_QUALITY_VALID);
    d.center_z_m = value(2.25); q = afsc_pose_quality(&p, &d, &s, 1);
    assert(q.reason == AFSC_QUALITY_DEPTH_WARNING && q.severity == AFSC_SEVERITY_WARNING);
    d.center_z_m = value(2.251); q = afsc_pose_quality(&p, &d, &s, 1);
    assert(q.reason == AFSC_QUALITY_DEPTH_REJECTED && q.severity == AFSC_SEVERITY_BAD);
    d.center_z_m = {}; q = afsc_pose_quality(&p, &d, &s, 1);
    assert(q.reason == AFSC_QUALITY_MISSING_DEPTH && !q.depth_difference_m.available);
    d.confidence = value(0); assert(afsc_pose_quality(&p, &d, &s, 1).reason == AFSC_QUALITY_LOW_CONFIDENCE_DEPTH);
    assert(afsc_pose_quality(&p, &d, &s, 0).reason == AFSC_QUALITY_TRACKING_LIMITED);
    p.ambiguous = 1; assert(afsc_pose_quality(&p, &d, &s, 1).reason == AFSC_QUALITY_AMBIGUOUS);
    p.ambiguous = 0; p.corrected_bits = value(1);
    assert(afsc_pose_quality(&p, &d, &s, 1).reason == AFSC_QUALITY_LOW_CONFIDENCE_POSE);
    p = pose(); p.orientation_available = 0;
    assert(afsc_pose_quality(&p, &d, &s, 1).reason == AFSC_QUALITY_POSE_UNAVAILABLE);
}
void heights() {
    auto i = heightInput(); auto h = afsc_floor_height(&i);
    assert(h.available && h.source == AFSC_HEIGHT_SOURCE_DEPTH); near(h.height_m, 2.2);
    near(h.world_m.x, 1.2); near(h.world_m.z, 1); near(h.floor_foot_world_m.y, 0);
    near(h.optical_m.x, 0.2); near(h.depth_difference_m.value, 0.1);
    i.floor.normal = {-0.1, 1, -0.2}; h = afsc_floor_height(&i); near(h.height_m, 1.88);
    i = heightInput(); i.depth = {}; h = afsc_floor_height(&i);
    assert(h.available && h.source == AFSC_HEIGHT_SOURCE_POSE && h.severity == AFSC_SEVERITY_WARNING);
    near(h.height_m, 2.21); assert(!h.accepted_depth_z_m.available);
    i.depth = {value(100), value(0)}; h = afsc_floor_height(&i);
    assert(h.available && h.source == AFSC_HEIGHT_SOURCE_POSE);
    i = heightInput(); i.depth.center_z_m = value(2.251);
    assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_DEPTH_MISMATCH);
    i = heightInput(); i.same_segment = 0; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_SEGMENT_MISMATCH);
    i = heightInput(); i.frame_age_s = 0.401; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_STALE_FRAME);
    i.frame_age_s = -0.01; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_STALE_FRAME);
    i.frame_age_s = std::numeric_limits<double>::quiet_NaN(); assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_STALE_FRAME);
    i = heightInput(); i.floor.normal = {1, 0.001, 0}; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_INVALID_INTERSECTION);
    i = heightInput(); i.floor.origin.y = 10; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_INVALID_INTERSECTION);
    i = heightInput(); i.floor.origin.y = -40; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_INVALID_INTERSECTION);
    for (int component : {0, 3, 15}) {
        i = heightInput(); i.world_from_optical.values[component] += 0.1;
        assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_INVALID_POSE);
    }
    i = heightInput(); i.world_from_optical.values[0] = 0.5;
    assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_INVALID_POSE);
    i = heightInput(); i.pose.ambiguous = -1; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_AMBIGUOUS_POSE);
    i = heightInput(); i.center_available = 0; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_INVALID_CENTER);
    i.depth = {}; assert(afsc_floor_height(&i).available); // Center pixels optional without depth.
    i = heightInput(); i.tracking_usable = 0; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_TRACKING_LIMITED);
    i = heightInput(); i.floor_available = 0; assert(afsc_floor_height(&i).reason == AFSC_HEIGHT_FLOOR_NOT_SELECTED);
    assert(afsc_floor_height(nullptr).reason == AFSC_HEIGHT_FLOOR_NOT_SELECTED);
}
void tagSize() {
    assert(afsc_measured_tag_size(2, 1, 1, .01, value(.1651)));
    assert(!afsc_measured_tag_size(2, 1, 0, .01, value(.1651)));
    assert(!afsc_measured_tag_size(2, 0, 1, .01, value(.1651)));
    assert(!afsc_measured_tag_size(1, 1, 1, .01, value(.1651)));
    assert(!afsc_measured_tag_size(2, 1, 1, .51, value(.1651)));
    assert(!afsc_measured_tag_size(2, 1, 1, .01, value(7)));
    assert(!afsc_measured_tag_size(2, 1, 1, .01, {}));
}
}
int main() {
    ranges(); quality(); heights(); tagSize();
    std::cout << "measurement core: ranges, quality, heights, and tag-size checks passed\n";
}
