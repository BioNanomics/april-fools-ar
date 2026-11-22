#include "afsc_projection.h"
#include <algorithm>
#include <array>
#include <cmath>

namespace {
bool finite(AFSCVec3 p) { return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z); }
bool optical(const AFSCProjection& c, AFSCVec3 p, AFSCVec3& out) {
    if (!finite(p)) return false;
    const double* m=c.world_to_optical.values;
    out={m[0]*p.x+m[4]*p.y+m[8]*p.z+m[12], m[1]*p.x+m[5]*p.y+m[9]*p.z+m[13], m[2]*p.x+m[6]*p.y+m[10]*p.z+m[14]};
    const double w=m[3]*p.x+m[7]*p.y+m[11]*p.z+m[15];
    return finite(out)&&std::isfinite(w)&&std::abs(w-1)<1e-3;
}
bool display(const AFSCProjection& c, AFSCVec3 p, AFSCVec2& out) {
    if (!(p.z>=c.near_meters*(1-1e-5))) return false;
    const double x=(c.intrinsics.values[0]*p.x/p.z+c.intrinsics.values[6])/c.image_width;
    const double y=(c.intrinsics.values[4]*p.y/p.z+c.intrinsics.values[7])/c.image_height;
    out={(c.affine[0]*x+c.affine[2]*y+c.affine[4])*c.viewport_width,
         (c.affine[1]*x+c.affine[3]*y+c.affine[5])*c.viewport_height};
    return std::isfinite(out.x)&&std::isfinite(out.y);
}
AFSCVec3 lerp(AFSCVec3 a, AFSCVec3 b, double t) { return {a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t}; }
}

int afsc_projection_init(AFSCMat4 transform, AFSCIntrinsics k, const double affine[6],
    double iw,double ih,double vw,double vh,double near,AFSCProjection* out) {
    if (!out) return 0;
    *out={};
    if (!affine||!std::isfinite(iw)||!std::isfinite(ih)||!std::isfinite(vw)||!std::isfinite(vh)||!std::isfinite(near)||iw<=0||ih<=0||vw<=0||vh<=0||near<=0) return 0;
    for (double v:k.values) if (!std::isfinite(v)) return 0;
    for (double v:transform.values) if (!std::isfinite(v)) return 0;
    for (int i=0;i<6;++i) if (!std::isfinite(affine[i])) return 0;
    if (k.values[0]<=0||k.values[4]<=0||std::abs(affine[0]*affine[3]-affine[1]*affine[2])<=1e-12) return 0;
    double a[4][8]={};
    for (int r=0;r<4;++r) for(int col=0;col<4;++col) {a[r][col]=transform.values[col*4+r];a[r][col+4]=(r==col?1:0);}
    double det=1;
    for(int col=0;col<4;++col) {
        int pivot=col;
        for(int r=col+1;r<4;++r) if(std::abs(a[r][col])>std::abs(a[pivot][col])) pivot=r;
        if(a[pivot][col]==0) return 0;
        if(pivot!=col){for(int j=0;j<8;++j) std::swap(a[col][j],a[pivot][j]);det=-det;}
        double scale=a[col][col];det*=scale;
        for(int j=0;j<8;++j) a[col][j]/=scale;
        for(int r=0;r<4;++r) if(r!=col){double factor=a[r][col];for(int j=0;j<8;++j)a[r][j]-=factor*a[col][j];}
    }
    if(!std::isfinite(det)||std::abs(det)<=1e-8) return 0;
    for(int r=0;r<4;++r)for(int col=0;col<4;++col){double v=a[r][col+4];if(!std::isfinite(v))return 0;out->world_to_optical.values[col*4+r]=v;}
    out->intrinsics=k;std::copy(affine,affine+6,out->affine);
    out->image_width=iw;out->image_height=ih;out->viewport_width=vw;out->viewport_height=vh;out->near_meters=near;
    return 1;
}
int afsc_project_point(const AFSCProjection* c,AFSCVec3 p,AFSCVec2* out) {
    if (!out) return 0;
    *out={};AFSCVec3 o{};return c&&optical(*c,p,o)&&display(*c,o,*out);
}
int afsc_project_segment(const AFSCProjection* c,AFSCVec3 start,AFSCVec3 end,AFSCVec2 out[2]) {
    if(!c||!out)return 0;
    out[0]={};out[1]={};AFSCVec3 a{},b{};
    if(!optical(*c,start,a)||!optical(*c,end,b)||(a.z<c->near_meters&&b.z<c->near_meters))return 0;
    if(a.z<c->near_meters){a=lerp(a,b,(c->near_meters-a.z)/(b.z-a.z));a.z=c->near_meters;}
    else if(b.z<c->near_meters){b=lerp(b,a,(c->near_meters-b.z)/(a.z-b.z));b.z=c->near_meters;}
    AFSCVec2 p{},q{};if(!display(*c,a,p)||!display(*c,b,q))return 0;
    double dx=q.x-p.x,dy=q.y-p.y,lo=0,hi=1;
    double directions[]={-dx,dx,-dy,dy},offsets[]={p.x,c->viewport_width-p.x,p.y,c->viewport_height-p.y};
    for(int i=0;i<4;++i){if(std::abs(directions[i])<1e-12){if(offsets[i]<0)return 0;continue;}
        double ratio=offsets[i]/directions[i];if(directions[i]<0)lo=std::max(lo,ratio);else hi=std::min(hi,ratio);if(lo>hi)return 0;}
    out[0]={p.x+lo*dx,p.y+lo*dy};out[1]={p.x+hi*dx,p.y+hi*dy};
    return std::isfinite(out[0].x)&&std::isfinite(out[0].y)&&std::isfinite(out[1].x)&&std::isfinite(out[1].y);
}
size_t afsc_project_polygon(const AFSCProjection* c,const AFSCVec3* world,size_t count,AFSCVec2* output,size_t capacity) {
    if(!c||!world||!output||count<3||count>AFSC_MAX_POLYGON_INPUT||capacity<3)return 0;
    std::array<AFSCVec3,AFSC_MAX_POLYGON_INPUT*2> clipped{};
    AFSCVec3 previous{};if(!optical(*c,world[count-1],previous))return 0;
    size_t n=0;
    for(size_t i=0;i<count;++i){AFSCVec3 current{};if(!optical(*c,world[i],current))return 0;
        bool a=previous.z>=c->near_meters,b=current.z>=c->near_meters;
        if(a!=b){auto p=lerp(previous,current,(c->near_meters-previous.z)/(current.z-previous.z));p.z=c->near_meters;clipped[n++]=p;}
        if(b)clipped[n++]=current;previous=current;
    }
    if(n<3)return 0;
    std::array<AFSCVec2,AFSC_MAX_POLYGON_OUTPUT> vertices{},scratch{};
    for(size_t i=0;i<n;++i)if(!display(*c,clipped[i],vertices[i]))return 0;
    for(int edge=0;edge<4;++edge){size_t next=0;AFSCVec2 prev=vertices[n-1];
        auto distance=[&](AFSCVec2 p){return edge==0?p.x:edge==1?c->viewport_width-p.x:edge==2?p.y:c->viewport_height-p.y;};
        for(size_t i=0;i<n;++i){auto cur=vertices[i];double a=distance(prev),b=distance(cur);
            if((a>=0)!=(b>=0)){if(next>=scratch.size())return 0;double t=a/(a-b);scratch[next++]={prev.x+(cur.x-prev.x)*t,prev.y+(cur.y-prev.y)*t};}
            if(b>=0){if(next>=scratch.size())return 0;scratch[next++]=cur;}prev=cur;
        }
        if(next<3)return 0;n=next;vertices.swap(scratch);
    }
    if(n>capacity)return 0;
    for(size_t i=0;i<n;++i){if(!std::isfinite(vertices[i].x)||!std::isfinite(vertices[i].y))return 0;output[i]=vertices[i];}
    return n;
}
