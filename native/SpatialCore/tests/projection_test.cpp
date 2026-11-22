#include "afsc_projection.h"
#include <cassert>
#include <cmath>
#include <limits>
int main() {
    AFSCMat4 pose{}; for(int i=0;i<4;++i)pose.values[i*5]=1;
    AFSCIntrinsics k{};k.values[0]=100;k.values[4]=100;k.values[6]=50;k.values[7]=50;k.values[8]=1;
    double affine[]={1,0,0,1,0,0};AFSCProjection c{};
    assert(afsc_projection_init(pose,k,affine,100,100,200,200,0.01,&c));
    AFSCVec2 p{};assert(afsc_project_point(&c,{0,0,1},&p));assert(p.x==100&&p.y==100);
    assert(!afsc_project_point(&c,{0,0,-1},&p));
    assert(afsc_project_point(&c,{0.1,0.2,1},&p));assert(std::abs(p.x-120)<1e-9&&std::abs(p.y-140)<1e-9);
    AFSCVec2 line[2]{};assert(afsc_project_segment(&c,{-2,0,1},{2,0,1},line));assert(line[0].x==0&&line[1].x==200);
    assert(afsc_project_segment(&c,{0,0,-1},{0,0,1},line));
    AFSCVec3 polygon[]={{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}};
    AFSCVec2 clipped[8]{};assert(afsc_project_polygon(&c,polygon,4,clipped,8)==4);
    for(auto q:clipped)assert(q.x>=0&&q.x<=200&&q.y>=0&&q.y<=200);
    assert(afsc_project_polygon(&c,polygon,4,clipped,3)==0);
    pose.values[0]=0;assert(!afsc_projection_init(pose,k,affine,100,100,200,200,0.01,&c));
    assert(!afsc_projection_init(pose,k,affine,0,100,200,200,0.01,&c));
    assert(!afsc_project_point(nullptr,{0,0,1},&p));
    // Optical frame +Y down; rotated/cropped display transform is applied after K.
    pose.values[0]=1;double rotate[]={0,1,-1,0,1,0};
    assert(afsc_projection_init(pose,k,rotate,100,100,200,200,0.01,&c));
    assert(afsc_project_point(&c,{0.1,0.2,1},&p));assert(std::abs(p.x-60)<1e-9&&std::abs(p.y-120)<1e-9);
}
