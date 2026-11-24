#include "afsc_fields.h"
#include "afsc_size_standards_generated.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <new>
#include <string>
#include <tuple>
#include <unordered_set>
#include <vector>

namespace {
constexpr double pi = 3.14159265358979323846;
bool isFinite(double x) { return std::isfinite(x); }
bool isFinite(AFSCVec3 p) { return isFinite(p.x) && isFinite(p.y) && isFinite(p.z); }
bool present(AFSCOptionalDouble x) { return x.available && isFinite(x.value); }
AFSCOptionalDouble some(double x) { return {1, x}; }
double dot(AFSCVec3 a, AFSCVec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
double norm(AFSCVec3 p) { return std::hypot(std::hypot(p.x,p.y),p.z); }
AFSCVec3 scaled(AFSCVec3 p, double s) { return {p.x*s,p.y*s,p.z*s}; }
AFSCVec3 plus(AFSCVec3 a, AFSCVec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
AFSCVec3 translation(const AFSCMat4 &m) { return {m.values[12],m.values[13],m.values[14]}; }
AFSCVec3 column(const AFSCMat4 &m, int c) { return {m.values[c*4],m.values[c*4+1],m.values[c*4+2]}; }
AFSCVec3 rotate(const AFSCMat4 &m, AFSCVec3 p) {
    return {m.values[0]*p.x+m.values[4]*p.y+m.values[8]*p.z,
            m.values[1]*p.x+m.values[5]*p.y+m.values[9]*p.z,
            m.values[2]*p.x+m.values[6]*p.y+m.values[10]*p.z};
}
bool rigid(const AFSCMat4 &m) {
    for (double v : m.values) if (!isFinite(v)) return false;
    if (std::abs(m.values[3])>=1e-4 || std::abs(m.values[7])>=1e-4 ||
        std::abs(m.values[11])>=1e-4 || std::abs(m.values[15]-1)>=1e-4) return false;
    for (int a=0;a<3;++a) for (int b=0;b<3;++b)
        if (std::abs(dot(column(m,a),column(m,b))-(a==b?1.:0.))>=1e-3) return false;
    const auto *v=m.values;
    const double determinant=v[0]*(v[5]*v[10]-v[9]*v[6])-
        v[4]*(v[1]*v[10]-v[9]*v[2])+v[8]*(v[1]*v[6]-v[5]*v[2]);
    return isFinite(determinant) && std::abs(determinant-1)<1e-3;
}
AFSCMat4 multiply(const AFSCMat4 &a,const AFSCMat4 &b) {
    AFSCMat4 m{};
    for(int c=0;c<4;++c) for(int r=0;r<4;++r) for(int k=0;k<4;++k)
        m.values[c*4+r]+=a.values[k*4+r]*b.values[c*4+k];
    return m;
}
bool viewValid(AFSCStringView v,size_t maximum) {
    return v.data && v.size>0 && v.size<=maximum && !std::memchr(v.data,0,v.size);
}
AFSCFieldCheckState comparison(double residual,double tolerance) {
    return std::abs(residual)<=tolerance+1e-12?AFSC_FIELD_PASS:AFSC_FIELD_FAIL;
}
}

extern "C" AFSCMat4 afsc_field_identity(void) {
    return {{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}};
}
extern "C" uint32_t afsc_field_transform_from_pose(AFSCVec3 t,const double q[4],AFSCMat4 *out) {
    if(!out) return 0;
    *out={};
    if(!q || !isFinite(t)) return 0;
    for(int n=0;n<4;++n) if(!isFinite(q[n])) return 0;
    const double magnitude=std::hypot(std::hypot(q[0],q[1]),std::hypot(q[2],q[3]));
    if(!isFinite(magnitude) || std::abs(magnitude-1)>1e-3) return 0;
    const double w=q[0]/magnitude,x=q[1]/magnitude,y=q[2]/magnitude,z=q[3]/magnitude;
    auto m=afsc_field_identity();
    m.values[0]=1-2*(y*y+z*z); m.values[4]=2*(x*y-z*w); m.values[8]=2*(x*z+y*w);
    m.values[1]=2*(x*y+z*w); m.values[5]=1-2*(x*x+z*z); m.values[9]=2*(y*z-x*w);
    m.values[2]=2*(x*z-y*w); m.values[6]=2*(y*z+x*w); m.values[10]=1-2*(x*x+y*y);
    m.values[12]=t.x;m.values[13]=t.y;m.values[14]=t.z;
    if(!rigid(m)) return 0;
    *out=m; return 1;
}
extern "C" uint32_t afsc_field_compose(AFSCMat4 a,AFSCMat4 b,AFSCMat4 *out) {
    if(!out) return 0;
    *out={}; if(!rigid(a)||!rigid(b)) return 0;
    const auto m=multiply(a,b); if(!rigid(m)) return 0;
    *out=m;return 1;
}
extern "C" uint32_t afsc_field_inverse(AFSCMat4 m,AFSCMat4 *out) {
    if(!out) return 0;
    *out={}; if(!rigid(m)) return 0;
    auto inverse=afsc_field_identity();
    for(int c=0;c<3;++c) for(int r=0;r<3;++r) inverse.values[c*4+r]=m.values[r*4+c];
    const auto t=scaled(rotate(inverse,translation(m)),-1);
    inverse.values[12]=t.x;inverse.values[13]=t.y;inverse.values[14]=t.z;
    if(!rigid(inverse)) return 0;
    *out=inverse;return 1;
}
extern "C" uint32_t afsc_field_transform_point(AFSCMat4 m,AFSCVec3 p,AFSCVec3 *out) {
    if(!out) return 0;
    *out={}; if(!rigid(m)||!isFinite(p)) return 0;
    const auto value=plus(rotate(m,p),translation(m));if(!isFinite(value)) return 0;
    *out=value;return 1;
}
extern "C" uint32_t afsc_field_raw_tag_from_wpilib(AFSCMat4 pose,AFSCMat4 *out) {
    const AFSCMat4 layoutFromRaw={{0,1,0,0, 0,0,-1,0, -1,0,0,0, 0,0,0,1}};
    return afsc_field_compose(pose,layoutFromRaw,out);
}
extern "C" uint32_t afsc_field_observed_tag(AFSCMat4 camera,AFSCMat4 tag,AFSCMat4 *out) {
    const AFSCMat4 axes={{1,0,0,0, 0,-1,0,0, 0,0,-1,0, 0,0,0,1}};
    AFSCMat4 optical{};
    if(!afsc_field_compose(camera,axes,&optical)) {if(out)*out={};return 0;}
    return afsc_field_compose(optical,tag,out);
}
extern "C" uint32_t afsc_field_gravity(AFSCMat4 pose,AFSCVec3 up,AFSCVec3 *tagUp,double *tilt) {
    if(tagUp)*tagUp={}; if(tilt)*tilt=0;
    if(!tagUp||!tilt||!rigid(pose)||!isFinite(up)) return 0;
    const double length=norm(up);if(!isFinite(length)||length<=1e-12) return 0;
    up=scaled(up,1/length);
    AFSCVec3 value={dot(column(pose,0),up),dot(column(pose,1),up),dot(column(pose,2),up)};
    const double tagLength=norm(value);if(!isFinite(tagLength)||tagLength<=1e-12) return 0;
    value=scaled(value,1/tagLength);
    *tagUp=value;
    *tilt=std::asin(std::clamp(std::abs(value.z),0.,1.));
    return 1;
}
extern "C" uint32_t afsc_field_registration(AFSCMat4 world,AFSCMat4 field,AFSCMat4 *out) {
    if(!out)return 0;
    *out={};AFSCMat4 inverse{},proposal{};
    if(!afsc_field_inverse(field,&inverse)||!afsc_field_compose(world,inverse,&proposal)) return 0;
    const double horizontal=std::hypot(proposal.values[0],proposal.values[2]);
    if(!isFinite(horizontal)||horizontal<=1e-8) return 0;
    const double x=proposal.values[0]/horizontal,z=proposal.values[2]/horizontal;
    AFSCMat4 m={{x,0,z,0, z,0,-x,0, 0,1,0,0, 0,0,0,1}};
    const auto t=plus(translation(world),scaled(rotate(m,translation(field)),-1));
    m.values[12]=t.x;m.values[13]=t.y;m.values[14]=t.z;
    if(!rigid(m))return 0;
    *out=m;return 1;
}
extern "C" AFSCAnchorCheck afsc_field_check_anchor(const AFSCAnchorInput *i) {
    AFSCAnchorCheck out{};out.reason=AFSC_ANCHOR_INVALID_INPUT;
    if(!i||!rigid(i->field_from_tag)||!isFinite(i->height_tolerance_m)||i->height_tolerance_m<=0||
        !isFinite(i->tilt_tolerance_rad)||i->tilt_tolerance_rad<=0||i->tilt_tolerance_rad>pi||
        !isFinite(i->gravity_tolerance_rad)||i->gravity_tolerance_rad<=0||i->gravity_tolerance_rad>pi) return out;
    AFSCVec3 expectedGravity{};double expectedTilt=0;
    if(!afsc_field_gravity(i->field_from_tag,{0,0,1},&expectedGravity,&expectedTilt))return out;
    out.expected_tilt_rad=some(expectedTilt);
    if(i->floor_datum_available) {
        const double height=i->field_from_tag.values[14]-i->field_floor_z_m;
        if(!isFinite(i->field_floor_z_m)||!isFinite(height)||height<0)return out;
        out.expected_height_m=some(height);
    }
    if(!i->fixed_reference){out.reason=AFSC_ANCHOR_NOT_FIXED;return out;}
    if(!i->same_segment){out.reason=AFSC_ANCHOR_SEGMENT_MISMATCH;return out;}
    if(!i->pose_usable||!rigid(i->world_from_tag)){out.reason=AFSC_ANCHOR_POSE_UNAVAILABLE;return out;}
    AFSCVec3 observedGravity{};double observedTilt=0;
    if(!afsc_field_gravity(i->world_from_tag,{0,1,0},&observedGravity,&observedTilt))return out;
    out.observed_tilt_rad=some(observedTilt);
    out.tilt_difference_rad=some(std::abs(observedTilt-expectedTilt));
    out.gravity_difference_rad=some(std::acos(std::clamp(dot(expectedGravity,observedGravity),-1.,1.)));
    out.tilt_status=comparison(out.tilt_difference_rad.value,i->tilt_tolerance_rad);
    out.gravity_status=comparison(out.gravity_difference_rad.value,i->gravity_tolerance_rad);
    if(out.expected_height_m.available && present(i->observed_height_m) && i->observed_height_m.value>=0) {
        out.observed_height_m=i->observed_height_m;
        out.height_difference_m=some(i->observed_height_m.value-out.expected_height_m.value);
        out.height_status=comparison(out.height_difference_m.value,i->height_tolerance_m);
    }
    if(out.height_status==AFSC_FIELD_FAIL){out.status=AFSC_FIELD_FAIL;out.reason=AFSC_ANCHOR_HEIGHT_MISMATCH;}
    else if(out.tilt_status==AFSC_FIELD_FAIL){out.status=AFSC_FIELD_FAIL;out.reason=AFSC_ANCHOR_TILT_MISMATCH;}
    else if(out.gravity_status==AFSC_FIELD_FAIL){out.status=AFSC_FIELD_FAIL;out.reason=AFSC_ANCHOR_GRAVITY_MISMATCH;}
    else if(out.height_status!=AFSC_FIELD_PASS){out.reason=AFSC_ANCHOR_HEIGHT_UNAVAILABLE;}
    else {out.status=AFSC_FIELD_PASS;out.reason=AFSC_ANCHOR_VALID;}
    return out;
}

extern "C" AFSCSizeResolution afsc_field_resolve_size(const AFSCSizeInput *i) {
    AFSCSizeResolution out{};out.reason=AFSC_SIZE_INVALID_INPUT;out.standard_index=-1;
    if(!i)return out;
    if(!i->automatic) {
        if(!present(i->selected_edge_m)||i->selected_edge_m.value<=0)return out;
        out.selected=1;out.reason=AFSC_SIZE_SELECTED;out.edge_m=i->selected_edge_m;
        if(isFinite(i->reference_edge_m)&&i->reference_edge_m>0) {
            const double factor=i->selected_edge_m.value/i->reference_edge_m;
            if(isFinite(factor)&&factor>0)out.scale=some(factor);
        }
        return out;
    }
    if(!isFinite(i->settings.max_range_m)||i->settings.max_range_m<=0||
       !isFinite(i->settings.max_plane_angle_rad)||i->settings.max_plane_angle_rad<=0||
       !isFinite(i->settings.max_reprojection_rms_px)||i->settings.max_reprojection_rms_px<=0)return out;
    if(!i->tracking_usable){out.reason=AFSC_SIZE_TRACKING_UNAVAILABLE;return out;}
    if(!present(i->depth.confidence)||i->depth.confidence.value!=2||
       !present(i->depth.center_z_m)||i->depth.center_z_m.value<=0||i->depth.center_z_m.value>i->settings.max_range_m) {
        out.reason=AFSC_SIZE_DEPTH_UNAVAILABLE;return out;
    }
    const auto &p=i->pose;
    if(!isFinite(i->reference_edge_m)||i->reference_edge_m<=0||!p.translation_available||
       !isFinite(p.translation)||p.translation.z<=0||p.ambiguous!=0||
       !present(p.reprojection_rms_px)||p.reprojection_rms_px.value<0||p.reprojection_rms_px.value>i->settings.max_reprojection_rms_px||
       !present(p.plane_angle_rad)||p.plane_angle_rad.value<0||p.plane_angle_rad.value>i->settings.max_plane_angle_rad||
       !present(p.decision_margin)||p.decision_margin.value<=0||!present(p.corrected_bits)||p.corrected_bits.value!=0) {
        out.reason=AFSC_SIZE_POSE_UNAVAILABLE;return out;
    }
    const double estimate=i->reference_edge_m*i->depth.center_z_m.value/p.translation.z;
    if(!isFinite(estimate)||estimate<=0)return out;
    out.estimated_edge_m=some(estimate);
    static constexpr AFSCSizeStandard defaults[]=AFSC_SIZE_STANDARD_INITIALIZERS;
    const AFSCSizeStandard *standards=i->standards;size_t count=i->standard_count;
    if(!standards&&count==0){standards=defaults;count=AFSC_SIZE_STANDARD_COUNT;}
    if(!standards||count==0||count>64)return out;
    int match=-1;size_t matches=0;
    for(size_t n=0;n<count;++n) {
        const auto &s=standards[n];
        if(!isFinite(s.edge_m)||s.edge_m<=0||!isFinite(s.relative_tolerance)||s.relative_tolerance<=0||s.relative_tolerance>1)return out;
        if(std::abs(estimate-s.edge_m)/s.edge_m<=s.relative_tolerance+1e-12){match=static_cast<int>(n);++matches;}
    }
    if(matches!=1){out.reason=AFSC_SIZE_NO_UNIQUE_MATCH;return out;}
    const double factor=standards[match].edge_m/i->reference_edge_m;
    const auto t=scaled(p.translation,factor);const double range=norm(t);
    if(!isFinite(factor)||!isFinite(t)||!isFinite(range)||range<=0||range>i->settings.max_range_m){out.reason=AFSC_SIZE_TOO_FAR;return out;}
    out.selected=1;out.reason=AFSC_SIZE_SELECTED;out.standard_index=match;
    out.edge_m=some(standards[match].edge_m);out.relative_tolerance=some(standards[match].relative_tolerance);
    out.scale=some(factor);return out;
}
extern "C" AFSCRescaledMetricPose afsc_field_rescale_metric_pose(const AFSCMetricPose *p,double edge) {
    AFSCRescaledMetricPose out{};
    if(!p||!isFinite(p->translation)||p->translation.z<=0||!isFinite(p->reference_edge_m)||p->reference_edge_m<=0||!isFinite(edge)||edge<=0)return out;
    const double scale=edge/p->reference_edge_m;
    const auto t=scaled(p->translation,scale);const double range=norm(t);
    if(!isFinite(scale)||scale<=0||!isFinite(t)||t.z<=0||!isFinite(range)||range<=0)return out;
    auto convert=[&](AFSCOptionalDouble source,double factor,AFSCOptionalDouble &destination) {
        if(!source.available)return true;
        if(!present(source)||source.value<0)return false;
        const double value=source.value*factor;
        if(!isFinite(value))return false;
        destination=some(value);return true;
    };
    if(!convert(p->pose_error_m2,scale*scale,out.pose_error_m2)||
       !convert(p->second_pose_error_m2,scale*scale,out.second_pose_error_m2)||
       !convert(p->candidate_translation_separation_m,scale,out.candidate_translation_separation_m))return {};
    out.available=1;out.translation=t;out.edge_m=edge;out.range_m=range;return out;
}

namespace {
struct ObservationKey {
    std::string family,segment,frame;int32_t id;
    bool operator==(const ObservationKey &other)const {
        return id==other.id&&family==other.family&&segment==other.segment&&frame==other.frame;
    }
};
struct ObservationHash {
    size_t operator()(const ObservationKey &k)const {
        size_t value=std::hash<std::string>{}(k.family);
        for(const auto *s:{&k.segment,&k.frame})value^=std::hash<std::string>{}(*s)+0x9e3779b9+(value<<6)+(value>>2);
        return value^(std::hash<int32_t>{}(k.id)+0x9e3779b9+(value<<6)+(value>>2));
    }
};
struct WalkRow {std::string family;int32_t id;uint64_t count=0,accepted=0,rejected=0;double first=0,last=0;};
}
struct AFSCFieldWalk {
    size_t maximum_rows,maximum_observations;
    std::vector<WalkRow> rows;
    std::map<std::pair<std::string,int32_t>,size_t> indices;
    std::unordered_set<ObservationKey,ObservationHash> observations;
};
extern "C" AFSCFieldWalk *afsc_field_walk_create(size_t rows,size_t observations) {
    if(rows==0||rows>4096||observations==0||observations>1000000)return nullptr;
    try {auto *walk=new AFSCFieldWalk();walk->maximum_rows=rows;walk->maximum_observations=observations;return walk;}
    catch(...){return nullptr;}
}
extern "C" void afsc_field_walk_destroy(AFSCFieldWalk *walk){delete walk;}
extern "C" void afsc_field_walk_clear(AFSCFieldWalk *walk){if(walk){walk->rows.clear();walk->indices.clear();walk->observations.clear();}}
extern "C" AFSCWalkResult afsc_field_walk_observe(AFSCFieldWalk *walk,AFSCStringView family,int32_t id,
    AFSCStringView segment,AFSCStringView frame,double timestamp,uint32_t accepted) {
    if(!walk||!viewValid(family,31)||!viewValid(segment,256)||!viewValid(frame,256)||id<0||!isFinite(timestamp)||timestamp<0||accepted>1)return AFSC_WALK_INVALID;
    try {
        ObservationKey key{std::string(family.data,family.size),std::string(segment.data,segment.size),std::string(frame.data,frame.size),id};
        if(walk->observations.find(key)!=walk->observations.end())return AFSC_WALK_DUPLICATE;
        const auto rowKey=std::make_pair(key.family,id);
        auto found=walk->indices.find(rowKey);
        const bool newRow=found==walk->indices.end();
        if(walk->observations.size()>=walk->maximum_observations||(newRow&&walk->rows.size()>=walk->maximum_rows))return AFSC_WALK_CAPACITY;
        const auto inserted=walk->observations.insert(key);
        size_t index=0;
        try {
            if(newRow) {
                index=walk->rows.size();walk->rows.push_back({key.family,id,0,0,0,timestamp,timestamp});
                try {walk->indices.emplace(rowKey,index);}catch(...){walk->rows.pop_back();throw;}
            } else index=found->second;
        } catch(...) {walk->observations.erase(inserted.first);throw;}
        auto &row=walk->rows[index];++row.count;if(accepted)++row.accepted;else ++row.rejected;
        row.first=std::min(row.first,timestamp);row.last=std::max(row.last,timestamp);
        return AFSC_WALK_ADDED;
    }catch(...){return AFSC_WALK_CAPACITY;}
}
extern "C" size_t afsc_field_walk_count(const AFSCFieldWalk *walk){return walk?walk->rows.size():0;}
extern "C" uint32_t afsc_field_walk_row(const AFSCFieldWalk *walk,size_t index,AFSCFieldWalkRow *out) {
    if(!out)return 0;*out={};if(!walk||index>=walk->rows.size())return 0;
    const auto &row=walk->rows[index];
    *out={row.family.c_str(),row.id,row.count,row.accepted,row.rejected,row.first,row.last};return 1;
}
