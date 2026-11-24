#include "afsc_geometry.h"
#include <cassert>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>

namespace {
constexpr double pi=3.14159265358979323846264338327950288;
bool near(double actual, double expected, double tolerance=1e-10) {
    return std::abs(actual-expected)<=tolerance;
}
double dot(AFSCVec3 a, AFSCVec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
AFSCVec3 sub(AFSCVec3 a, AFSCVec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
AFSCVec3 cross(AFSCVec3 a, AFSCVec3 b) {
    return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};
}
void makeCloud(AFSCVec3 *points, double a, double b, AFSCVec3 origin, double zScale=1) {
    for (size_t i=0; i<144; ++i) {
        const double x=static_cast<double>(i%12)/11*2-1;
        const double z=(static_cast<double>(i/12)/11*2-1)*zScale;
        points[i]={origin.x+x,origin.y+a*x+b*z,origin.z+z};
    }
}
void testAnalyticPlanes() {
    AFSCVec3 points[144];
    for (double degrees : {0.0,2.0,5.0}) {
        const double a=std::tan(degrees*pi/180);
        makeCloud(points,a,0,{0,1.7,0});
        AFSCFloorFit fit{};
        assert(afsc_floor_fit(points,144,{0,0},&fit)==AFSC_GEOMETRY_OK);
        assert(near(fit.tilt_radians,degrees*pi/180));
        assert(near(fit.plane.origin.y,1.7));
        assert(near(fit.plane.normal.x,-std::sin(degrees*pi/180)));
        assert(near(fit.plane.normal.y,std::cos(degrees*pi/180)));
        assert(fit.sample_count==144 && fit.inlier_count==144 && fit.rms_meters<1e-12);
    }
    const double a=std::tan(3*pi/180), b=std::tan(2*pi/180);
    makeCloud(points,a,b,{1000,7.25,-2000});
    AFSCFloorFit fit{};
    assert(afsc_floor_fit(points,144,{1000,-2000},&fit)==AFSC_GEOMETRY_OK);
    assert(near(fit.tilt_radians,std::atan(std::hypot(a,b))));
    assert(fit.plane.origin.x==1000 && fit.plane.origin.z==-2000 && near(fit.plane.origin.y,7.25));
}
void testRobustDeterminismAndBounds() {
    AFSCVec3 points[512];
    makeCloud(points,std::tan(4*pi/180),0,{0,1.7,0});
    for (size_t i=0; i<144; ++i) points[i].y+=(i%5==0) ? 0.22 : std::sin(static_cast<double>(i)*1.7)*0.006;
    AFSCFloorFit fit{}, replay{};
    assert(afsc_floor_fit(points,144,{0,0},&fit)==AFSC_GEOMETRY_OK);
    assert(afsc_floor_fit(points,144,{0,0},&replay)==AFSC_GEOMETRY_OK);
    assert(near(fit.tilt_radians,4*pi/180,0.15*pi/180));
    assert(near(fit.plane.origin.y,1.7,0.005));
    assert(fit.inlier_count>=110 && fit.inlier_count<144 && fit.rms_meters<0.01);
    assert(fit.tilt_radians==replay.tilt_radians && fit.inlier_count==replay.inlier_count);
    assert(fit.plane.normal.x==replay.plane.normal.x && fit.plane.normal.y==replay.plane.normal.y);
    assert(fit.plane.origin.y==replay.plane.origin.y && fit.rms_meters==replay.rms_meters);
    for (size_t i=0; i<512; ++i) {
        const double x=static_cast<double>(i%32)/31*2-1, z=static_cast<double>(i/32)/15*2-1;
        points[i]={x,0.05*x+0.02*z,z};
    }
    assert(afsc_floor_fit(points,512,{0,0},&fit)==AFSC_GEOMETRY_OK);
    assert(fit.inlier_count==512);
    assert(afsc_floor_fit(points,31,{0,0},&fit)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    assert(afsc_floor_fit(points,513,{0,0},&fit)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    assert(afsc_floor_fit(nullptr,144,{0,0},&fit)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    assert(afsc_floor_fit(points,144,{0,0},nullptr)==AFSC_GEOMETRY_INVALID_ARGUMENT);
}
void testRejectedFitsLeaveOutputUnchanged() {
    AFSCVec3 points[144];
    AFSCFloorFit fit{};
    fit.rms_meters=42;
    makeCloud(points,0,0,{0,0,0},0.01);
    assert(afsc_floor_fit(points,144,{0,0},&fit)==AFSC_GEOMETRY_DEGENERATE);
    assert(fit.rms_meters==42);
    makeCloud(points,std::tan(30*pi/180),0,{0,0,0});
    assert(afsc_floor_fit(points,144,{0,0},&fit)==AFSC_GEOMETRY_DEGENERATE);
    for (size_t i=0; i<144; ++i) points[i]={static_cast<double>(i)/32,1,static_cast<double>(i)/16};
    assert(afsc_floor_fit(points,144,{0,0},&fit)==AFSC_GEOMETRY_DEGENERATE);
    makeCloud(points,0,0,{0,0,0});
    points[10].y=std::numeric_limits<double>::quiet_NaN();
    assert(afsc_floor_fit(points,144,{0,0},&fit)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    assert(fit.rms_meters==42);
    makeCloud(points,0.03,0,{0,0,0});
    for (size_t i=0; i<144; ++i) if (i%3) points[i].y+=(static_cast<int>(i%11)-5)*0.15;
    assert(afsc_floor_fit(points,144,{0,0},&fit)==AFSC_GEOMETRY_DEGENERATE);
    assert(afsc_floor_fit(points,144,{INFINITY,0},&fit)==AFSC_GEOMETRY_INVALID_ARGUMENT);
}
void testVerticalFootTiltAndDistance() {
    AFSCVec3 foot{};
    const AFSCPlane plane={{0,0,0},{-0.1,1,-0.2}};
    assert(afsc_vertical_foot({2,3,4},plane,&foot)==AFSC_GEOMETRY_OK);
    assert(foot.x==2 && near(foot.y,1) && foot.z==4);
    assert(afsc_vertical_foot({2,3,4},{{0,0,0},{0.1,-1,0.2}},&foot)==AFSC_GEOMETRY_OK);
    assert(near(foot.y,1));
    foot={7,8,9};
    assert(afsc_vertical_foot({0,-1,0},plane,&foot)==AFSC_GEOMETRY_OUT_OF_RANGE);
    assert(foot.x==7 && foot.y==8 && foot.z==9);
    assert(afsc_vertical_foot({0,31,0},plane,&foot)==AFSC_GEOMETRY_OUT_OF_RANGE);
    assert(afsc_vertical_foot({0,30,0},plane,&foot)==AFSC_GEOMETRY_OK);
    assert(afsc_vertical_foot({0,1,0},{{0,0,0},{1,0,0}},&foot)==AFSC_GEOMETRY_INVALID_PLANE);
    assert(afsc_vertical_foot({NAN,1,0},plane,&foot)==AFSC_GEOMETRY_INVALID_PLANE);
    double tilt=42;
    assert(afsc_floor_tilt({-0.1,1,-0.2},&tilt)==AFSC_GEOMETRY_OK);
    assert(near(tilt,std::atan(std::hypot(0.1,0.2))));
    assert(afsc_floor_tilt({0,-1,0},&tilt)==AFSC_GEOMETRY_OK && tilt==0);
    assert(afsc_floor_tilt({0,0,0},&tilt)==AFSC_GEOMETRY_INVALID_PLANE && tilt==0);
    assert(afsc_floor_tilt({NAN,1,0},&tilt)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    AFSCDistance distance{};
    assert(afsc_distance({1,2,3},{4,6,15},&distance)==AFSC_GEOMETRY_OK);
    assert(near(distance.distance_meters,13) && near(distance.horizontal_meters,std::sqrt(153.0)) && distance.vertical_meters==4);
    assert(afsc_distance({0,1,0},{0,0,0},&distance)==AFSC_GEOMETRY_OK && distance.vertical_meters==-1);
    assert(afsc_distance({0,0,0},{0,0,0},&distance)==AFSC_GEOMETRY_OK && distance.distance_meters==0);
    assert(afsc_distance({INFINITY,0,0},{0,0,0},&distance)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    assert(afsc_distance({-1e308,0,0},{1e308,0,0},&distance)==AFSC_GEOMETRY_OUT_OF_RANGE);
}
void testDistanceTriangle() {
    AFSCDistanceTriangle triangle{};
    const AFSCVec3 start={1,2,3}, end={4,6,3};
    assert(afsc_distance_triangle(start,end,&triangle)==AFSC_GEOMETRY_OK);
    assert(triangle.corner.x==4 && triangle.corner.y==2 && triangle.corner.z==3);
    assert(near(triangle.lengths.distance_meters,5) && near(triangle.lengths.horizontal_meters,3)
        && triangle.lengths.vertical_meters==4);
    assert(near(dot(sub(triangle.corner,start),sub(end,triangle.corner)),0));
    assert(afsc_distance_triangle(end,start,&triangle)==AFSC_GEOMETRY_OK);
    assert(triangle.corner.x==1 && triangle.corner.y==6 && triangle.corner.z==3);
    assert(near(triangle.lengths.distance_meters,5) && near(triangle.lengths.horizontal_meters,3)
        && triangle.lengths.vertical_meters==-4);
    for (const auto finish : {AFSCVec3{4,2,7}, AFSCVec3{1,-2,3}, start}) {
        assert(afsc_distance_triangle(start,finish,&triangle)==AFSC_GEOMETRY_OK);
        assert(triangle.corner.x==finish.x && triangle.corner.y==start.y && triangle.corner.z==finish.z);
        AFSCDistance horizontal{}, vertical{};
        assert(afsc_distance(start,triangle.corner,&horizontal)==AFSC_GEOMETRY_OK);
        assert(afsc_distance(triangle.corner,finish,&vertical)==AFSC_GEOMETRY_OK);
        assert(near(horizontal.distance_meters,triangle.lengths.horizontal_meters));
        assert(near(vertical.distance_meters,std::abs(triangle.lengths.vertical_meters)));
        assert(near(std::hypot(horizontal.distance_meters,vertical.distance_meters),triangle.lengths.distance_meters));
    }
    // A gravity-aligned world may translate and rotate around +Y. The lengths
    // remain invariant, and the constructed right-angle corner moves with it.
    for (double yaw : {-pi, -.37, 0., .81, pi/2}) {
        const auto transform = [yaw](AFSCVec3 p) {
            return AFSCVec3{100+std::cos(yaw)*p.x-std::sin(yaw)*p.z,
                p.y-7, -20+std::sin(yaw)*p.x+std::cos(yaw)*p.z};
        };
        assert(afsc_distance_triangle(transform(start),transform(end),&triangle)==AFSC_GEOMETRY_OK);
        const auto expectedCorner=transform({end.x,start.y,end.z});
        assert(near(triangle.corner.x,expectedCorner.x) && near(triangle.corner.y,expectedCorner.y)
            && near(triangle.corner.z,expectedCorner.z));
        assert(near(triangle.lengths.distance_meters,5) && near(triangle.lengths.horizontal_meters,3)
            && near(triangle.lengths.vertical_meters,4));
    }
    const AFSCDistanceTriangle sentinel={{7,8,9},{10,11,12}};
    for (const auto invalid : {AFSCVec3{NAN,2,3}, AFSCVec3{1,INFINITY,3}, AFSCVec3{1,2,-INFINITY}}) {
        triangle=sentinel;
        assert(afsc_distance_triangle(invalid,end,&triangle)==AFSC_GEOMETRY_INVALID_ARGUMENT);
        assert(std::memcmp(&triangle,&sentinel,sizeof(triangle))==0);
        assert(afsc_distance_triangle(start,invalid,&triangle)==AFSC_GEOMETRY_INVALID_ARGUMENT);
        assert(std::memcmp(&triangle,&sentinel,sizeof(triangle))==0);
    }
    triangle=sentinel;
    assert(afsc_distance_triangle({-1e308,0,0},{1e308,0,0},&triangle)==AFSC_GEOMETRY_OUT_OF_RANGE);
    assert(std::memcmp(&triangle,&sentinel,sizeof(triangle))==0);
    assert(afsc_distance_triangle(start,end,nullptr)==AFSC_GEOMETRY_INVALID_ARGUMENT);
}
void testCoverageAndMarker() {
    AFSCVec3 rectangle[4];
    const double rotation=pi/4;
    const double x[4]={-0.05,0.05,0.05,-0.05}, z[4]={-5,-5,5,5};
    for (size_t i=0;i<4;++i) rectangle[i]={1000+x[i]*std::cos(rotation)-z[i]*std::sin(rotation),7,-2000+x[i]*std::sin(rotation)+z[i]*std::cos(rotation)};
    AFSCFloorCoverage coverage{};
    assert(afsc_floor_coverage(rectangle,4,&coverage)==AFSC_GEOMETRY_OK);
    assert(near(coverage.area_square_meters,1,1e-9) && near(coverage.min_span_meters,0.1,1e-9));
    assert(afsc_floor_coverage(rectangle,2,&coverage)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    rectangle[0].y=NAN;
    assert(afsc_floor_coverage(rectangle,4,&coverage)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    const AFSCPlane plane={{2,-1,4},{std::sin(5*pi/180),std::cos(5*pi/180),0}};
    AFSCQuad quad{};
    assert(afsc_floor_marker(plane.origin,plane,0.3,&quad)==AFSC_GEOMETRY_OK);
    const AFSCVec3 points[4]={quad.p0,quad.p1,quad.p2,quad.p3};
    for (size_t i=0;i<4;++i) {
        AFSCDistance distance{};
        assert(afsc_distance(points[i],points[(i+1)%4],&distance)==AFSC_GEOMETRY_OK);
        assert(near(distance.distance_meters,0.3));
        assert(near(dot(sub(points[i],plane.origin),plane.normal),0));
    }
    assert(dot(cross(sub(points[1],points[0]),sub(points[2],points[1])),plane.normal)>0);
    AFSCQuad replay{};
    assert(afsc_floor_marker(plane.origin,plane,0.3,&replay)==AFSC_GEOMETRY_OK);
    assert(replay.p0.x==quad.p0.x && replay.p0.y==quad.p0.y && replay.p0.z==quad.p0.z);
    assert(afsc_floor_marker({2,-0.99,4},plane,0.3,&quad)==AFSC_GEOMETRY_INVALID_PLANE);
    assert(afsc_floor_marker(plane.origin,plane,0,&quad)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    assert(afsc_floor_marker(plane.origin,plane,INFINITY,&quad)==AFSC_GEOMETRY_INVALID_ARGUMENT);
    assert(afsc_floor_marker({1e20,0,1e20},{{1e20,0,1e20},{0,1,0}},0.3,&quad)==AFSC_GEOMETRY_DEGENERATE);
}
} // namespace
int main() {
    testAnalyticPlanes(); testRobustDeterminismAndBounds(); testRejectedFitsLeaveOutputUnchanged();
    testVerticalFootTiltAndDistance(); testDistanceTriangle(); testCoverageAndMarker();
    std::cout << "Geometry tests passed\n";
}
