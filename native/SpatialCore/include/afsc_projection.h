#ifndef AFSC_PROJECTION_H
#define AFSC_PROJECTION_H
#include "afsc_types.h"
#ifdef __cplusplus
extern "C" {
#endif
#define AFSC_MAX_POLYGON_INPUT 512
#define AFSC_MAX_POLYGON_OUTPUT 8192
/* Pure numerical debug projection. Display affine transforms normalized source
 * image coordinates into normalized viewport coordinates (a,b,c,d,tx,ty). */
typedef struct {
    AFSCMat4 world_to_optical;
    AFSCIntrinsics intrinsics;
    double affine[6];
    double image_width, image_height, viewport_width, viewport_height, near_meters;
} AFSCProjection;
/* Returns 1 on success, 0 on invalid/singular input. No pointers retained. */
int afsc_projection_init(AFSCMat4 optical_to_world, AFSCIntrinsics intrinsics,
    const double affine[6], double image_width, double image_height,
    double viewport_width, double viewport_height, double near_meters, AFSCProjection *output);
int afsc_project_point(const AFSCProjection *camera, AFSCVec3 world, AFSCVec2 *output);
int afsc_project_segment(const AFSCProjection *camera, AFSCVec3 start, AFSCVec3 end, AFSCVec2 output[2]);
/* Clips before perspective divide, then to viewport. 0 means hidden/invalid or
 * insufficient output capacity; caller owns all buffers. Input count <=512. */
size_t afsc_project_polygon(const AFSCProjection *camera, const AFSCVec3 *world,
    size_t count, AFSCVec2 *output, size_t capacity);
#ifdef __cplusplus
}
#endif
#endif
