#ifndef AFSC_TYPES_H
#define AFSC_TYPES_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define AFSC_ABI_VERSION 1
/* All lengths are metres, angles radians, transforms column-major T_destination_source.
 * Camera coordinates are optical: +X right, +Y down, +Z forward. World is gravity +Y up.
 * Inputs are borrowed for the duration of a call. No library function retains pointers.
 * Missing values are explicit; confidence categories are not statistical covariance. */
typedef struct { double x, y; } AFSCVec2;
typedef struct { double x, y, z; } AFSCVec3;
typedef struct { double values[16]; } AFSCMat4;
typedef struct { double values[9]; } AFSCIntrinsics;
typedef struct { AFSCVec3 origin, normal; } AFSCPlane;
typedef struct { AFSCVec3 p0, p1, p2, p3; } AFSCQuad;
typedef struct { const char *data; size_t size; } AFSCStringView;
/* Metadata must travel with observations/replay. Strings are opaque and never hashed.
 * Clock domains must be mapped before combining observations from different devices.
 * segment_id changes on world reset. covariance_known=0 means unknown, not zero error. */
typedef struct {
    AFSCStringView sensor_id, calibration_id, frame_id, segment_id, clock_domain, coordinate_frame;
    int64_t timestamp_ns;
    uint32_t covariance_known;
    double position_covariance[9];
} AFSCObservationHeader;
uint32_t afsc_abi_version(void);
const char *afsc_version(void);
#ifdef __cplusplus
}
#endif
#endif
