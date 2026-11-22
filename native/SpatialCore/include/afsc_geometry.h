#ifndef AFSC_GEOMETRY_H
#define AFSC_GEOMETRY_H
#include "afsc_types.h"
#ifdef __cplusplus
extern "C" {
#endif

/* All functions are allocation-free, retain no pointers, and leave output unchanged
 * on failure. Angles are radians and distances are metres. */
typedef enum {
    AFSC_GEOMETRY_OK = 0,
    AFSC_GEOMETRY_INVALID_ARGUMENT = 1,
    AFSC_GEOMETRY_INVALID_PLANE = 2,
    AFSC_GEOMETRY_OUT_OF_RANGE = 3,
    AFSC_GEOMETRY_DEGENERATE = 4
} AFSCGeometryStatus;

typedef struct {
    AFSCPlane plane;
    double tilt_radians;
    size_t sample_count;
    size_t inlier_count;
    double rms_meters;
} AFSCFloorFit;

typedef struct {
    double distance_meters;
    double vertical_meters; /* signed end.y - start.y */
    double horizontal_meters;
} AFSCDistance;

typedef struct {
    double area_square_meters;
    double min_span_meters;
} AFSCFloorCoverage;

/* Deterministic 128-hypothesis robust fit of y=a*x+b*z+c. Accepts 32..512
 * points, >=65% consensus (at least 24), <=20 degree tilt, <=3 cm RMS;
 * inliers have <=4 cm vertical residual. Requires a broad 2D footprint.
 * reference_xz fixes the returned plane origin's world X and Z. */
AFSCGeometryStatus afsc_floor_fit(const AFSCVec3 *points, size_t count,
                                AFSCVec2 reference_xz, AFSCFloorFit *result);
AFSCGeometryStatus afsc_floor_tilt(AFSCVec3 normal, double *tilt_radians);
/* Plane must have |normal.y|/length >= 0.8. Height must be in [0,30].
 * INVALID_PLANE identifies unsuitable plane geometry; OUT_OF_RANGE identifies
 * a target outside the supported height interval. */
AFSCGeometryStatus afsc_vertical_foot(AFSCVec3 target, AFSCPlane plane, AFSCVec3 *foot);
/* Horizontal polygon coverage, including rotation-invariant minimum edge-normal
 * span. Vertex order must follow the polygon boundary; convex floor boundaries
 * give the intended minimum-width interpretation. At least three vertices. */
AFSCGeometryStatus afsc_floor_coverage(const AFSCVec3 *vertices, size_t count,
                                     AFSCFloorCoverage *coverage);
/* Square centred on the plane, using a fixed world-X-derived basis and upward
 * winding. Centre must be within 0.1 mm of an approximately horizontal plane. */
AFSCGeometryStatus afsc_floor_marker(AFSCVec3 center, AFSCPlane plane,
                                    double side_meters, AFSCQuad *corners);
AFSCGeometryStatus afsc_distance(AFSCVec3 start, AFSCVec3 end, AFSCDistance *distance);
#ifdef __cplusplus
}
#endif
#endif
