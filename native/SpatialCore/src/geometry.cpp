#include "afsc_geometry.h"
#include <cmath>
#include <cstdint>
#include <limits>

namespace {
constexpr size_t kMinSamples = 32;
constexpr size_t kMaxSamples = 512;
constexpr double kPi = 3.14159265358979323846264338327950288;
constexpr double kMaxTilt = 20.0 * kPi / 180.0;
constexpr double kInlierTolerance = 0.04;
struct Model { double a, b, c; };

bool finite(AFSCVec3 v) { return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z); }
AFSCVec3 subtract(AFSCVec3 a, AFSCVec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
AFSCVec3 scale(AFSCVec3 v, double s) { return {v.x*s, v.y*s, v.z*s}; }
double dot(AFSCVec3 a, AFSCVec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
double length(AFSCVec3 v) { return std::hypot(std::hypot(v.x, v.y), v.z); }
AFSCVec3 cross(AFSCVec3 a, AFSCVec3 b) {
    return {a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x};
}
double tilt(const Model &m) { return std::atan(std::hypot(m.a, m.b)); }
double residual(const Model &m, AFSCVec3 p) { return std::abs(p.y-(m.a*p.x+m.b*p.z+m.c)); }
bool finite(const Model &m) { return std::isfinite(m.a) && std::isfinite(m.b) && std::isfinite(m.c); }

bool through(AFSCVec3 p, AFSCVec3 q, AFSCVec3 r, Model &m) {
    const double dx1=q.x-p.x, dz1=q.z-p.z, dy1=q.y-p.y;
    const double dx2=r.x-p.x, dz2=r.z-p.z, dy2=r.y-p.y;
    const double determinant=dx1*dz2-dx2*dz1;
    if (!std::isfinite(determinant) || std::abs(determinant)<=1e-8) return false;
    m.a=(dy1*dz2-dy2*dz1)/determinant;
    m.b=(dx1*dy2-dx2*dy1)/determinant;
    m.c=p.y-m.a*p.x-m.b*p.z;
    return finite(m);
}

bool leastSquares(const AFSCVec3 *points, const size_t *indices, size_t count, Model &m) {
    if (count<24) return false;
    double meanX=0, meanY=0, meanZ=0;
    for (size_t i=0; i<count; ++i) {
        const auto p=points[indices[i]];
        meanX+=p.x; meanY+=p.y; meanZ+=p.z;
    }
    meanX/=static_cast<double>(count); meanY/=static_cast<double>(count); meanZ/=static_cast<double>(count);
    double xx=0, zz=0, xz=0, xy=0, zy=0;
    for (size_t i=0; i<count; ++i) {
        const auto p=points[indices[i]];
        const double x=p.x-meanX, y=p.y-meanY, z=p.z-meanZ;
        xx+=x*x; zz+=z*z; xz+=x*z; xy+=x*y; zy+=z*y;
    }
    const double trace=xx+zz, discriminant=std::hypot(xx-zz, 2*xz);
    const double minVariance=(trace-discriminant)/(2*static_cast<double>(count));
    const double maxVariance=(trace+discriminant)/(2*static_cast<double>(count));
    const double determinant=xx*zz-xz*xz;
    if (!std::isfinite(trace) || !std::isfinite(determinant) || determinant<=0 ||
        minVariance<0.0225 || !std::isfinite(maxVariance) || minVariance/maxVariance<0.0025) return false;
    m.a=(xy*zz-zy*xz)/determinant;
    m.b=(zy*xx-xy*xz)/determinant;
    m.c=meanY-m.a*meanX-m.b*meanZ;
    return finite(m);
}

bool floorNormal(AFSCPlane plane, double minimumLength, AFSCVec3 &normal) {
    if (!finite(plane.origin) || !finite(plane.normal)) return false;
    const double n=length(plane.normal);
    if (!std::isfinite(n) || n<=minimumLength || std::abs(plane.normal.y)/n<0.8) return false;
    normal=scale(plane.normal, 1/n);
    return finite(normal);
}
} // namespace

extern "C" AFSCGeometryStatus afsc_floor_fit(const AFSCVec3 *points, size_t count,
                                              AFSCVec2 reference, AFSCFloorFit *result) {
    if (!points || !result || count<kMinSamples || count>kMaxSamples ||
        !std::isfinite(reference.x) || !std::isfinite(reference.y)) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    double baselineY=0;
    for (size_t i=0; i<count; ++i) {
        if (!finite(points[i])) return AFSC_GEOMETRY_INVALID_ARGUMENT;
        baselineY+=points[i].y;
    }
    baselineY/=static_cast<double>(count);
    AFSCVec3 local[kMaxSamples];
    for (size_t i=0; i<count; ++i) {
        local[i]={points[i].x-reference.x, points[i].y-baselineY, points[i].z-reference.y};
        if (!finite(local[i])) return AFSC_GEOMETRY_DEGENERATE;
    }
    const size_t requiredInliers=static_cast<size_t>(std::fmax(24, std::ceil(static_cast<double>(count)*0.65)));
    size_t best[kMaxSamples], current[kMaxSamples], bestCount=0;
    double bestError=std::numeric_limits<double>::infinity();
    uint64_t random=UINT64_C(0xA9F1045D2B76C831);
    const auto nextIndex=[&random, count]() {
        random=random*UINT64_C(6364136223846793005)+UINT64_C(1442695040888963407);
        return static_cast<size_t>((random>>16)%count);
    };
    for (size_t iteration=0; iteration<128; ++iteration) {
        const size_t i=nextIndex(), j=nextIndex(), k=nextIndex();
        Model model{};
        if (i==j || i==k || j==k || !through(local[i], local[j], local[k], model) || tilt(model)>kMaxTilt) continue;
        size_t inlierCount=0;
        double error=0;
        for (size_t index=0; index<count; ++index) {
            const double r=residual(model, local[index]);
            if (r<=kInlierTolerance) { current[inlierCount++]=index; error+=r*r; }
        }
        if (inlierCount>bestCount || (inlierCount==bestCount && error<bestError)) {
            for (size_t index=0; index<inlierCount; ++index) best[index]=current[index];
            bestCount=inlierCount; bestError=error;
        }
    }
    if (bestCount<requiredInliers) return AFSC_GEOMETRY_DEGENERATE;
    for (size_t iteration=0; iteration<3; ++iteration) {
        Model model{};
        if (!leastSquares(local, best, bestCount, model) || tilt(model)>kMaxTilt) return AFSC_GEOMETRY_DEGENERATE;
        size_t currentCount=0;
        for (size_t i=0; i<count; ++i) if (residual(model, local[i])<=kInlierTolerance) current[currentCount++]=i;
        if (currentCount<requiredInliers) return AFSC_GEOMETRY_DEGENERATE;
        bool equal=currentCount==bestCount;
        for (size_t i=0; equal && i<currentCount; ++i) equal=current[i]==best[i];
        if (equal) break;
        for (size_t i=0; i<currentCount; ++i) best[i]=current[i];
        bestCount=currentCount;
    }
    Model model{};
    if (!leastSquares(local, best, bestCount, model)) return AFSC_GEOMETRY_DEGENERATE;
    const double tiltRadians=tilt(model);
    if (!std::isfinite(tiltRadians) || tiltRadians>kMaxTilt) return AFSC_GEOMETRY_DEGENERATE;
    double squaredError=0;
    for (size_t i=0; i<bestCount; ++i) { const double r=residual(model, local[best[i]]); squaredError+=r*r; }
    const double rms=std::sqrt(squaredError/static_cast<double>(bestCount));
    const double normalLength=std::hypot(std::hypot(model.a, model.b), 1.0);
    const AFSCPlane plane={{reference.x, baselineY+model.c, reference.y},
                           {-model.a/normalLength, 1/normalLength, -model.b/normalLength}};
    if (!std::isfinite(rms) || rms>0.03 || !finite(plane.origin) || !finite(plane.normal)) return AFSC_GEOMETRY_DEGENERATE;
    *result={plane, tiltRadians, count, bestCount, rms};
    return AFSC_GEOMETRY_OK;
}

extern "C" AFSCGeometryStatus afsc_floor_tilt(AFSCVec3 normal, double *radians) {
    if (!radians || !finite(normal)) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    const double lateral=std::hypot(normal.x, normal.z), vertical=std::abs(normal.y);
    if ((!std::isfinite(lateral)) || !(lateral>0 || vertical>0)) return AFSC_GEOMETRY_INVALID_PLANE;
    *radians=std::atan2(lateral, vertical);
    return AFSC_GEOMETRY_OK;
}

extern "C" AFSCGeometryStatus afsc_vertical_foot(AFSCVec3 target, AFSCPlane plane, AFSCVec3 *foot) {
    if (!foot) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    AFSCVec3 normal{};
    if (!finite(target) || !floorNormal(plane, 0, normal)) return AFSC_GEOMETRY_INVALID_PLANE;
    const double height=dot(plane.normal, subtract(target, plane.origin))/plane.normal.y;
    const AFSCVec3 value={target.x, target.y-height, target.z};
    if (!std::isfinite(height) || height<0 || height>30 || !finite(value)) return AFSC_GEOMETRY_OUT_OF_RANGE;
    *foot=value;
    return AFSC_GEOMETRY_OK;
}

extern "C" AFSCGeometryStatus afsc_floor_coverage(const AFSCVec3 *vertices, size_t count,
                                                   AFSCFloorCoverage *coverage) {
    if (!vertices || !coverage || count<3) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    for (size_t i=0; i<count; ++i) if (!finite(vertices[i])) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    const AFSCVec3 origin=vertices[0];
    double twiceArea=0, width=std::numeric_limits<double>::infinity();
    for (size_t i=0; i<count; ++i) {
        const auto a=subtract(vertices[i], origin), b=subtract(vertices[(i+1)%count], origin);
        if (!finite(a) || !finite(b)) return AFSC_GEOMETRY_DEGENERATE;
        twiceArea+=a.x*b.z-b.x*a.z;
        const double dx=b.x-a.x, dz=b.z-a.z, edgeLength=std::hypot(dx, dz);
        if (!std::isfinite(edgeLength) || edgeLength<=1e-8) continue;
        const double nx=-dz/edgeLength, nz=dx/edgeLength;
        double low=std::numeric_limits<double>::infinity(), high=-std::numeric_limits<double>::infinity();
        for (size_t j=0; j<count; ++j) {
            const double projection=(vertices[j].x-origin.x)*nx+(vertices[j].z-origin.z)*nz;
            if (!std::isfinite(projection)) return AFSC_GEOMETRY_DEGENERATE;
            low=std::fmin(low, projection); high=std::fmax(high, projection);
        }
        width=std::fmin(width, high-low);
    }
    const double area=std::abs(twiceArea)/2;
    if (!std::isfinite(area) || !std::isfinite(width)) return AFSC_GEOMETRY_DEGENERATE;
    *coverage={area, std::fmax(0, width)};
    return AFSC_GEOMETRY_OK;
}

extern "C" AFSCGeometryStatus afsc_floor_marker(AFSCVec3 center, AFSCPlane plane,
                                                 double side, AFSCQuad *corners) {
    if (!corners || !finite(center) || !std::isfinite(side) || side<=0) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    AFSCVec3 normal{};
    if (!floorNormal(plane, 1e-6, normal)) return AFSC_GEOMETRY_INVALID_PLANE;
    if (normal.y<0) normal=scale(normal, -1);
    const double planeDistance=dot(normal, subtract(center, plane.origin));
    if (!std::isfinite(planeDistance) || std::abs(planeDistance)>0.0001) return AFSC_GEOMETRY_INVALID_PLANE;
    const AFSCVec3 projectedX={1-normal.x*normal.x, -normal.y*normal.x, -normal.z*normal.x};
    const AFSCVec3 u=scale(projectedX, 1/length(projectedX));
    const AFSCVec3 crossed=cross(normal, u), v=scale(crossed, 1/length(crossed));
    if (!finite(u) || !finite(v)) return AFSC_GEOMETRY_DEGENERATE;
    const double half=side/2;
    AFSCVec3 points[4];
    constexpr int su[4]={-1,1,1,-1}, sv[4]={-1,-1,1,1};
    for (size_t i=0; i<4; ++i) {
        points[i]={center.x+su[i]*u.x*half+sv[i]*v.x*half,
                   center.y+su[i]*u.y*half+sv[i]*v.y*half,
                   center.z+su[i]*u.z*half+sv[i]*v.z*half};
        if (!finite(points[i])) return AFSC_GEOMETRY_DEGENERATE;
    }
    for (size_t i=0; i<4; ++i) {
        const double edge=length(subtract(points[(i+1)%4], points[i]));
        if (!std::isfinite(edge) || edge<=0) return AFSC_GEOMETRY_DEGENERATE;
    }
    *corners={points[0],points[1],points[2],points[3]};
    return AFSC_GEOMETRY_OK;
}

extern "C" AFSCGeometryStatus afsc_distance(AFSCVec3 start, AFSCVec3 end, AFSCDistance *distance) {
    if (!distance || !finite(start) || !finite(end)) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    const AFSCVec3 delta=subtract(end, start);
    const AFSCDistance value={length(delta), delta.y, std::hypot(delta.x, delta.z)};
    if (!std::isfinite(value.distance_meters) || !std::isfinite(value.vertical_meters) ||
        !std::isfinite(value.horizontal_meters)) return AFSC_GEOMETRY_OUT_OF_RANGE;
    *distance=value;
    return AFSC_GEOMETRY_OK;
}

extern "C" AFSCGeometryStatus afsc_distance_triangle(AFSCVec3 start, AFSCVec3 end,
                                                      AFSCDistanceTriangle *triangle) {
    if (!triangle) return AFSC_GEOMETRY_INVALID_ARGUMENT;
    AFSCDistance lengths{};
    const auto status = afsc_distance(start, end, &lengths);
    if (status != AFSC_GEOMETRY_OK) return status;
    *triangle = {{end.x, start.y, end.z}, lengths};
    return AFSC_GEOMETRY_OK;
}
