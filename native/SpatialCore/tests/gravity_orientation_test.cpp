#include "afsc_measurements.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>

namespace {
constexpr double pi = 3.14159265358979323846;
AFSCOptionalDouble value(double x) { return {1, x}; }
void near(double actual, double expected, double tolerance = 1e-10) {
    assert(std::abs(actual-expected) <= tolerance);
}
AFSCMat4 identity() { return {{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}}; }
AFSCMat4 multiply(const AFSCMat4 &a, const AFSCMat4 &b) {
    AFSCMat4 out{};
    for (int c = 0; c < 4; ++c) for (int r = 0; r < 4; ++r)
        for (int k = 0; k < 4; ++k) out.values[c*4+r] += a.values[k*4+r]*b.values[c*4+k];
    return out;
}
AFSCMat4 transposeRotation(const AFSCMat4 &a) {
    auto out = identity();
    for (int c = 0; c < 3; ++c) for (int r = 0; r < 3; ++r) out.values[c*4+r] = a.values[r*4+c];
    return out;
}
// Build an orthonormal physical tag basis directly. The plane's normal leans
// upwards by tilt; the printed right/up axes then rotate clockwise by twist.
AFSCMat4 tagInWorld(double tilt, double twist) {
    const double cb = std::cos(tilt), sb = std::sin(tilt), ct = std::cos(twist), st = std::sin(twist);
    return {{ct,-st*cb,-st*sb,0, -st,-ct*cb,-ct*sb,0, 0,sb,-cb,0, 0,0,0,1}};
}
AFSCGravityOrientationInput input() {
    AFSCGravityOrientationInput i{};
    i.tracking_usable = i.frame_id_available = 1;
    i.timestamp_s = 100; i.frame_age_s = 0.1;
    i.world_from_optical = {{1,0,0,0, 0,-1,0,0, 0,0,-1,0, 0,1.5,0,1}};
    i.optical_from_tag_rotation = identity();
    i.pose.translation_available = i.pose.orientation_available = 1;
    i.pose.translation = {0,0,3}; i.pose.range_m = value(3);
    i.pose.plane_angle_rad = value(0.1); i.pose.reprojection_rms_px = value(0.5);
    i.pose.corrected_bits = value(0); i.pose.decision_margin = value(80);
    i.settings = {10, pi/3, 3, 0.1, 0.15};
    return i;
}
void expectReason(const AFSCGravityOrientationInput &i, AFSCGravityOrientationReason reason) {
    const auto out = afsc_gravity_orientation(&i);
    assert(!out.available && out.reason == reason && !out.twist_rad.available);
}
void geometry() {
    auto i = input(); auto out = afsc_gravity_orientation(&i);
    assert(out.available && out.reason == AFSC_GRAVITY_ORIENTATION_VALID && out.twist_rad.available);
    near(out.tilt_from_vertical_rad, 0); near(out.twist_rad.value, 0);
    near(out.normal_world.z, -1); near(out.up_world.y, 1);
    near(out.world_from_tag_rotation.values[13], 0); // Camera position is irrelevant.
    for (double tilt : {-pi/3, -pi/6, 0., pi/6, pi/3, pi/2}) {
        for (double twist : {-pi, -pi/2, -0.3, 0., 0.4, pi/2, pi}) {
            const auto expected = tagInWorld(tilt, twist);
            i.optical_from_tag_rotation = multiply(transposeRotation(i.world_from_optical), expected);
            out = afsc_gravity_orientation(&i); assert(out.available);
            near(out.tilt_from_vertical_rad, std::abs(tilt));
            near(out.normal_world.y, std::sin(tilt));
            near(out.up_world.y, std::cos(twist)*std::cos(tilt));
            for (int n = 0; n < 16; ++n) near(out.world_from_tag_rotation.values[n], expected.values[n]);
            if (std::abs(tilt) < pi/2) {
                assert(out.twist_rad.available);
                // At +/-pi the two signed endpoints represent the same rotation.
                near(std::sin(out.twist_rad.value), std::sin(twist));
                near(std::cos(out.twist_rad.value), std::cos(twist));
            } else { assert(!out.twist_rad.available); }
        }
    }
    for (double offset : {0.00005, 0.0002}) {
        i.optical_from_tag_rotation = multiply(transposeRotation(i.world_from_optical), tagInWorld(pi/2-offset, .4));
        out = afsc_gravity_orientation(&i); assert(out.available);
        assert(static_cast<bool>(out.twist_rad.available) == (offset > 0.0001));
    }
    // An upside-down printed tag has zero plane lean and a 180-degree twist.
    i.optical_from_tag_rotation = multiply(transposeRotation(i.world_from_optical), tagInWorld(0, pi));
    out = afsc_gravity_orientation(&i); near(out.tilt_from_vertical_rad, 0); near(std::abs(out.twist_rad.value), pi);
}
AFSCMat4 axisRotation(int axis, double angle) {
    auto r = identity(); const int a = (axis+1)%3, b = (axis+2)%3;
    r.values[a*4+a] = r.values[b*4+b] = std::cos(angle);
    r.values[a*4+b] = std::sin(angle); r.values[b*4+a] = -std::sin(angle);
    return r;
}
void phoneMotionInvariance() {
    const auto expectedRotation = tagInWorld(.27, -.41);
    const auto opticalAxes = input().world_from_optical;
    for (int index = 0; index < 12; ++index) {
        auto i = input();
        // Vary all three phone rotation axes and its position while the physical
        // tag's world pose remains fixed. Never compose Euler components.
        const auto motion = multiply(axisRotation(2, .025*index),
            multiply(axisRotation(1, -.02*index), axisRotation(0, .015*index)));
        i.world_from_optical = multiply(motion, opticalAxes);
        i.world_from_optical.values[12] = .03*index;
        i.world_from_optical.values[13] = 1.5-.02*index;
        i.world_from_optical.values[14] = -.01*index;
        const auto opticalFromWorldRotation = transposeRotation(i.world_from_optical);
        i.optical_from_tag_rotation = multiply(opticalFromWorldRotation, expectedRotation);
        const double worldTag[3] = {.1, 1.6, -4};
        double opticalTranslation[3]{};
        for (int row = 0; row < 3; ++row) for (int k = 0; k < 3; ++k)
            opticalTranslation[row] += opticalFromWorldRotation.values[k*4+row]
                * (worldTag[k]-i.world_from_optical.values[12+k]);
        i.pose.translation = {opticalTranslation[0], opticalTranslation[1], opticalTranslation[2]};
        i.pose.range_m = value(std::hypot(std::hypot(opticalTranslation[0], opticalTranslation[1]), opticalTranslation[2]));
        const auto out = afsc_gravity_orientation(&i);
        assert(out.available && out.twist_rad.available);
        near(out.tilt_from_vertical_rad, .27); near(out.twist_rad.value, -.41);
        for (int n = 0; n < 16; ++n) near(out.world_from_tag_rotation.values[n], expectedRotation.values[n]);
    }
}
void rejection() {
    const double nan = std::numeric_limits<double>::quiet_NaN();
    auto i = input();
    assert(afsc_gravity_orientation(nullptr).reason == AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i.tracking_usable = 0; expectReason(i, AFSC_GRAVITY_ORIENTATION_TRACKING_LIMITED);
    for (double age : {-0.001, .400001, nan, std::numeric_limits<double>::infinity()}) {
        i = input(); i.frame_age_s = age; expectReason(i, AFSC_GRAVITY_ORIENTATION_STALE_FRAME);
    }
    i = input(); i.frame_age_s = .4; assert(afsc_gravity_orientation(&i).available);
    i = input(); i.frame_id_available = 0; expectReason(i, AFSC_GRAVITY_ORIENTATION_STALE_FRAME);
    i = input(); i.timestamp_s = nan; expectReason(i, AFSC_GRAVITY_ORIENTATION_STALE_FRAME);
    for (int ambiguous : {-1, 1, 2}) {
        i = input(); i.pose.ambiguous = ambiguous; expectReason(i, AFSC_GRAVITY_ORIENTATION_AMBIGUOUS_POSE);
    }
    for (int n : {0, 3, 7, 11, 15}) {
        i = input(); i.world_from_optical.values[n] += .1; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
        i = input(); i.optical_from_tag_rotation.values[n] += .1; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    }
    i = input(); i.world_from_optical.values[12] = nan; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.world_from_optical.values[0] = -1; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE); // Reflection.
    i = input(); i.optical_from_tag_rotation.values[0] = -1; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.optical_from_tag_rotation.values[12] = .1; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.pose.orientation_available = 0; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.pose.translation_available = 0; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    for (double z : {0., -1., nan}) {
        i = input(); i.pose.translation.z = z; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    }
    i = input(); i.pose.range_m = {}; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.pose.range_m = value(-1); expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.pose.range_m = value(11); expectReason(i, AFSC_GRAVITY_ORIENTATION_TOO_FAR);
    i = input(); i.pose.translation.z = 11; expectReason(i, AFSC_GRAVITY_ORIENTATION_TOO_FAR); // Cannot hide behind cached range.
    i = input(); i.pose.plane_angle_rad = value(1.1); expectReason(i, AFSC_GRAVITY_ORIENTATION_BAD_ANGLE);
    for (double angle : {-0.1, pi/2+.1, nan}) {
        i = input(); i.pose.plane_angle_rad = value(angle); expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    }
    i = input(); i.pose.plane_angle_rad = {}; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.pose.reprojection_rms_px = {}; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.pose.reprojection_rms_px = value(-1); expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.pose.reprojection_rms_px = value(4); expectReason(i, AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE);
    for (double bits : {-1., 1., nan}) {
        i = input(); i.pose.corrected_bits = value(bits); expectReason(i, AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE);
    }
    i = input(); i.pose.corrected_bits = {}; expectReason(i, AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE);
    for (double margin : {-1., 0., nan}) {
        i = input(); i.pose.decision_margin = value(margin); expectReason(i, AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE);
    }
    i = input(); i.pose.decision_margin = {}; expectReason(i, AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE);
    i = input(); i.settings.max_range_m = nan; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.settings.max_plane_angle_rad = 0; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.settings.max_plane_angle_rad = pi; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    i = input(); i.settings.max_reprojection_rms_px = -1; expectReason(i, AFSC_GRAVITY_ORIENTATION_INVALID_POSE);
    // Floor, depth, center pixels, intrinsics, and bearing are not inputs to this
    // measurement. Missing depth settings must not suppress gravity orientation.
    i = input(); i.settings.warning_depth_difference_m = i.settings.reject_depth_difference_m = nan;
    assert(!i.pose.bearing_rad.available && afsc_gravity_orientation(&i).available);
}
}
int main() {
    geometry(); phoneMotionInvariance(); rejection();
    std::cout << "gravity orientation: plane lean, printed twist, phone motion invariance, and validity gates passed\n";
}
