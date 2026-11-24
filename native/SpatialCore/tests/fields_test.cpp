#include "afsc_fields.h"
#include <cassert>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>

namespace {
constexpr double pi=3.14159265358979323846;
void near(double a,double b,double tolerance=1e-9){assert(std::abs(a-b)<=tolerance);}
void vectorNear(AFSCVec3 a,AFSCVec3 b){near(a.x,b.x);near(a.y,b.y);near(a.z,b.z);}
AFSCOptionalDouble value(double x){return {1,x};}
AFSCMat4 fieldTag() {
    // A zero-yaw WPILib face points along field +X. Construct raw D axes by
    // physical directions: right=+Y, down=-Z, into-print=-X.
    return {{0,1,0,0, 0,0,-1,0, -1,0,0,0, 2,3,1.5,1}};
}
AFSCMat4 worldTag() {
    // Independent field -> AR mapping: X->X, Y->-Z, Z->Y, offset(3,.2,-4).
    return {{0,0,-1,0, 0,-1,0,0, -1,0,0,0, 5,1.7,-7,1}};
}
AFSCAnchorInput anchor() {
    AFSCAnchorInput input{};
    input.fixed_reference=input.pose_usable=input.same_segment=input.floor_datum_available=1;
    input.field_from_tag=fieldTag();input.world_from_tag=worldTag();
    input.field_floor_z_m=0;input.observed_height_m=value(1.5);
    input.height_tolerance_m=.05;input.tilt_tolerance_rad=3*pi/180;input.gravity_tolerance_rad=5*pi/180;
    return input;
}
void transforms() {
    auto identity=afsc_field_identity();
    const double q[]={std::sqrt(.5),0,0,std::sqrt(.5)};
    AFSCMat4 pose{};assert(afsc_field_transform_from_pose({2,3,4},q,&pose));
    AFSCVec3 point{};assert(afsc_field_transform_point(pose,{1,0,0},&point));
    vectorNear(point,{2,4,4});
    AFSCMat4 inverse{},result{};assert(afsc_field_inverse(pose,&inverse));
    assert(afsc_field_compose(inverse,pose,&result));
    for(int n=0;n<16;++n)near(result.values[n],identity.values[n]);
    assert(afsc_field_transform_point(inverse,point,&point));vectorNear(point,{1,0,0});
    auto layout=identity;layout.values[12]=2;layout.values[13]=3;layout.values[14]=1.5;
    assert(afsc_field_raw_tag_from_wpilib(layout,&pose));
    for(int n=0;n<16;++n)near(pose.values[n],fieldTag().values[n]);
    auto camera=identity;camera.values[13]=1.5;
    auto optical=identity;optical.values[14]=3;
    assert(afsc_field_observed_tag(camera,optical,&pose));
    near(pose.values[13],1.5);near(pose.values[14],-3);near(pose.values[5],-1);near(pose.values[10],-1);
    const double zeroQ[]={0,0,0,0},badQ[]={2,0,0,0};
    assert(!afsc_field_transform_from_pose({0,0,0},zeroQ,&pose));near(pose.values[15],0);
    assert(!afsc_field_transform_from_pose({0,0,0},badQ,&pose));
    assert(!afsc_field_transform_from_pose({0,0,0},nullptr,&pose));
    assert(!afsc_field_transform_from_pose({0,0,0},q,nullptr));
    auto reflection=identity;reflection.values[0]=-1;
    assert(!afsc_field_inverse(reflection,&pose));
    auto invalid=identity;invalid.values[3]=.1;
    assert(!afsc_field_compose(invalid,identity,&pose));
    assert(!afsc_field_transform_point(identity,{0,std::numeric_limits<double>::quiet_NaN(),0},&point));
}
void registrationAndGravity() {
    AFSCVec3 up{};double tilt=-1;
    assert(afsc_field_gravity(fieldTag(),{0,0,1},&up,&tilt));
    vectorNear(up,{0,-1,0});near(tilt,0);
    assert(afsc_field_gravity(worldTag(),{0,1,0},&up,&tilt));
    vectorNear(up,{0,-1,0});near(tilt,0);
    AFSCMat4 registration{};assert(afsc_field_registration(worldTag(),fieldTag(),&registration));
    const AFSCMat4 expected={{1,0,0,0, 0,0,-1,0, 0,1,0,0, 3,.2,-4,1}};
    for(int n=0;n<16;++n)near(registration.values[n],expected.values[n]);
    AFSCVec3 observed{};assert(afsc_field_transform_point(registration,{2,3,1.5},&observed));
    vectorNear(observed,{5,1.7,-7});
    // Add independently known yaw: F +X becomes W +Z. Field +Z must remain W +Y.
    AFSCMat4 yawed={{-1,0,0,0, 0,-1,0,0, 0,0,1,0, 9,1.5,2,1}};
    assert(afsc_field_registration(yawed,fieldTag(),&registration));
    vectorNear({registration.values[8],registration.values[9],registration.values[10]},{0,1,0});
    assert(afsc_field_transform_point(registration,{2,3,1.5},&observed));vectorNear(observed,{9,1.5,2});
    assert(!afsc_field_gravity(fieldTag(),{0,0,0},&up,&tilt));
    assert(!afsc_field_gravity(fieldTag(),{0,0,1},nullptr,&tilt));
}
void anchorChecks() {
    auto i=anchor();auto check=afsc_field_check_anchor(&i);
    assert(check.status==AFSC_FIELD_PASS&&check.reason==AFSC_ANCHOR_VALID);
    near(check.expected_height_m.value,1.5);near(check.observed_height_m.value,1.5);
    near(check.expected_tilt_rad.value,0);near(check.gravity_difference_rad.value,0);
    // No registration is supplied to the check: an independently selected floor
    // decides observed height. A wrong height cannot be hidden by registering.
    i.observed_height_m=value(1.7);check=afsc_field_check_anchor(&i);
    assert(check.status==AFSC_FIELD_FAIL&&check.reason==AFSC_ANCHOR_HEIGHT_MISMATCH);
    near(check.height_difference_m.value,.2);
    i=anchor();i.observed_height_m={};check=afsc_field_check_anchor(&i);
    assert(check.status==AFSC_FIELD_UNAVAILABLE&&check.reason==AFSC_ANCHOR_HEIGHT_UNAVAILABLE);
    assert(check.tilt_status==AFSC_FIELD_PASS&&check.gravity_status==AFSC_FIELD_PASS);
    i=anchor();i.floor_datum_available=0;check=afsc_field_check_anchor(&i);
    assert(check.status==AFSC_FIELD_UNAVAILABLE&&!check.expected_height_m.available);
    i=anchor();i.same_segment=0;assert(afsc_field_check_anchor(&i).reason==AFSC_ANCHOR_SEGMENT_MISMATCH);
    i=anchor();i.fixed_reference=0;assert(afsc_field_check_anchor(&i).reason==AFSC_ANCHOR_NOT_FIXED);
    i=anchor();i.pose_usable=0;assert(afsc_field_check_anchor(&i).reason==AFSC_ANCHOR_POSE_UNAVAILABLE);
    i=anchor();i.height_tolerance_m=0;assert(afsc_field_check_anchor(&i).reason==AFSC_ANCHOR_INVALID_INPUT);
    i=anchor();i.field_floor_z_m=std::numeric_limits<double>::quiet_NaN();
    assert(afsc_field_check_anchor(&i).reason==AFSC_ANCHOR_INVALID_INPUT);
    i=anchor();i.field_floor_z_m=2;
    assert(afsc_field_check_anchor(&i).reason==AFSC_ANCHOR_INVALID_INPUT);
    i=anchor();i.field_from_tag.values[14]=std::numeric_limits<double>::max();
    i.field_floor_z_m=-std::numeric_limits<double>::max();
    check=afsc_field_check_anchor(&i);assert(check.reason==AFSC_ANCHOR_INVALID_INPUT&&!check.expected_height_m.available);
    assert(afsc_field_check_anchor(nullptr).reason==AFSC_ANCHOR_INVALID_INPUT);
    // Upside down: same height, same unsigned tilt, but reversed gravity in D.
    i=anchor();for(int n=0;n<3;++n){i.world_from_tag.values[n]*=-1;i.world_from_tag.values[4+n]*=-1;}
    check=afsc_field_check_anchor(&i);
    assert(check.height_status==AFSC_FIELD_PASS&&check.tilt_status==AFSC_FIELD_PASS);
    assert(check.status==AFSC_FIELD_FAIL&&check.reason==AFSC_ANCHOR_GRAVITY_MISMATCH);
    near(check.gravity_difference_rad.value,pi);
    // A correctly sloped reference (30deg) must not be forced upright.
    const double theta=pi/6,c=std::cos(theta),s=std::sin(theta);
    i=anchor();
    i.field_from_tag={{0,1,0,0, -s,0,-c,0, -c,0,s,0, 2,3,1.5,1}};
    i.world_from_tag={{0,0,-1,0, -s,-c,0,0, -c,s,0,0, 5,1.7,-7,1}};
    check=afsc_field_check_anchor(&i);assert(check.status==AFSC_FIELD_PASS);
    near(check.expected_tilt_rad.value,theta);near(check.observed_tilt_rad.value,theta);
    i.world_from_tag=worldTag();check=afsc_field_check_anchor(&i);
    assert(check.status==AFSC_FIELD_FAIL&&check.reason==AFSC_ANCHOR_TILT_MISMATCH);
    // Moving the tag horizontally is not detectable by height/gravity checks.
    // The adapter must retain provisional/anchor-dependent status after pass.
    i=anchor();i.world_from_tag.values[12]+=2;assert(afsc_field_check_anchor(&i).status==AFSC_FIELD_PASS);
}
AFSCSizeInput sizing() {
    AFSCSizeInput i{};i.automatic=i.tracking_usable=1;i.reference_edge_m=.1651;
    i.pose.translation_available=i.pose.orientation_available=1;i.pose.translation={.2,-.1,2};
    i.pose.ambiguous=0;i.pose.reprojection_rms_px=value(.5);i.pose.plane_angle_rad=value(.1);
    i.pose.decision_margin=value(80);i.pose.corrected_bits=value(0);
    i.depth.center_z_m=value(2);i.depth.confidence=value(2);
    i.settings={5,pi/3,3,.1,.15};return i;
}
void sizes() {
    const double widths[]={.0508,.08255,.1016,.127,.1524,.1651};
    for(int n=0;n<6;++n) {
        auto i=sizing();i.depth.center_z_m=value(2*widths[n]/.1651);
        const auto result=afsc_field_resolve_size(&i);assert(result.selected&&result.reason==AFSC_SIZE_SELECTED);
        near(result.edge_m.value,widths[n]);near(result.estimated_edge_m.value,widths[n]);
        near(result.scale.value,widths[n]/.1651);assert(result.standard_index==n);
        near(result.relative_tolerance.value,n<4?.10:.03);
    }
    auto i=sizing();i.tracking_usable=0;assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_TRACKING_UNAVAILABLE);
    for(double confidence:{0.,1.,3.}) {
        i=sizing();i.depth.confidence=value(confidence);assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_DEPTH_UNAVAILABLE);
    }
    i=sizing();i.depth.center_z_m={};assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_DEPTH_UNAVAILABLE);
    i=sizing();i.pose.ambiguous=1;assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_POSE_UNAVAILABLE);
    i=sizing();i.pose.corrected_bits=value(1);assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_POSE_UNAVAILABLE);
    i=sizing();i.pose.reprojection_rms_px=value(4);assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_POSE_UNAVAILABLE);
    i=sizing();i.pose.translation.z=0;assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_POSE_UNAVAILABLE);
    // The small gap between the nearby 6/6.5in acceptance windows must not snap.
    i=sizing();i.depth.center_z_m=value(2*.1585/.1651);
    assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_NO_UNIQUE_MATCH);
    i=sizing();i.depth.center_z_m=value(2*.1524*1.03/.1651);
    assert(afsc_field_resolve_size(&i).selected);
    i.depth.center_z_m=value(2*.1524*1.03001/.1651);
    assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_NO_UNIQUE_MATCH);
    const AFSCSizeStandard overlap[]={{.1,.1},{.105,.1}};
    i=sizing();i.standards=overlap;i.standard_count=2;i.depth.center_z_m=value(2*.103/.1651);
    assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_NO_UNIQUE_MATCH);
    i=sizing();i.pose.translation.x=100;assert(afsc_field_resolve_size(&i).reason==AFSC_SIZE_TOO_FAR);
    // Explicit sizing remains selected without depth/tracking/reference pose.
    i={};i.selected_edge_m=value(.08255);const auto explicitResult=afsc_field_resolve_size(&i);
    assert(explicitResult.selected);near(explicitResult.edge_m.value,.08255);assert(!explicitResult.scale.available);
    i.selected_edge_m={};assert(!afsc_field_resolve_size(&i).selected);
    assert(!afsc_field_resolve_size(nullptr).selected);
    AFSCMetricPose metric{};metric.reference_edge_m=.1651;metric.translation={1,2,4};
    metric.pose_error_m2=value(.04);metric.second_pose_error_m2=value(.08);metric.candidate_translation_separation_m=value(.2);
    const auto scaled=afsc_field_rescale_metric_pose(&metric,.08255);assert(scaled.available);
    vectorNear(scaled.translation,{.5,1,2});near(scaled.range_m,std::sqrt(5.25));
    near(scaled.pose_error_m2.value,.01);near(scaled.second_pose_error_m2.value,.02);
    near(scaled.candidate_translation_separation_m.value,.1);
    metric.pose_error_m2={};assert(!afsc_field_rescale_metric_pose(&metric,.08255).pose_error_m2.available);
    metric.reference_edge_m=0;assert(!afsc_field_rescale_metric_pose(&metric,.08255).available);
}
AFSCStringView view(const char *s){return {s,std::strlen(s)};}
void inventory() {
    auto *walk=afsc_field_walk_create(3,5);assert(walk);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),20,view("s1"),view("f1"),10,1)==AFSC_WALK_ADDED);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),20,view("s1"),view("f1"),11,0)==AFSC_WALK_DUPLICATE);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),20,view("s1"),view("f2"),9,0)==AFSC_WALK_ADDED);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),20,view("s2"),view("f1"),12,1)==AFSC_WALK_ADDED);
    AFSCFieldWalkRow row{};assert(afsc_field_walk_row(walk,0,&row));
    assert(std::string(row.family)=="tag36h11"&&row.tag_id==20&&row.observation_count==3);
    assert(row.accepted_count==2&&row.rejected_count==1);near(row.first_seen_s,9);near(row.last_seen_s,12);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),999,view("s2"),view("f1"),13,0)==AFSC_WALK_ADDED);
    assert(afsc_field_walk_observe(walk,view("other"),20,view("s2"),view("f1"),14,1)==AFSC_WALK_ADDED);
    assert(afsc_field_walk_count(walk)==3);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),20,view("s2"),view("f2"),15,1)==AFSC_WALK_CAPACITY);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),-1,view("s2"),view("f2"),15,1)==AFSC_WALK_INVALID);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),20,{},view("f2"),15,1)==AFSC_WALK_INVALID);
    assert(!afsc_field_walk_row(walk,3,&row));
    afsc_field_walk_clear(walk);assert(afsc_field_walk_count(walk)==0);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),20,view("s1"),view("f1"),10,1)==AFSC_WALK_ADDED);
    afsc_field_walk_destroy(walk);
    assert(!afsc_field_walk_create(0,5));assert(!afsc_field_walk_create(5,0));
    assert(!afsc_field_walk_create(5000,5));assert(!afsc_field_walk_create(5,1000001));
    assert(afsc_field_walk_count(nullptr)==0);afsc_field_walk_destroy(nullptr);afsc_field_walk_clear(nullptr);
    walk=afsc_field_walk_create(1,5);assert(walk);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),1,view("s"),view("f1"),1,0)==AFSC_WALK_ADDED);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),2,view("s"),view("f2"),2,0)==AFSC_WALK_CAPACITY);
    assert(afsc_field_walk_observe(walk,view("tag36h11"),1,view("s"),view("f2"),2,0)==AFSC_WALK_ADDED);
    afsc_field_walk_destroy(walk);
}
}
int main(){transforms();registrationAndGravity();anchorChecks();sizes();inventory();std::cout<<"Field geometry, independent anchor checks, size policy and bounded inventory passed\n";}
