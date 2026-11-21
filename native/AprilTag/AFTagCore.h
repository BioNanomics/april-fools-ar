#ifndef AF_TAG_CORE_H
#define AF_TAG_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AFTagCore AFTagCore;
typedef struct {
    int id;
    char family[16];
    int hamming;
    double decisionMargin;
    double center[2];
    double corners[4][2];
} AFTagDetection;

enum { AFTagCoreSuccess = 0, AFTagCoreInvalidInput = 1, AFTagCoreOutOfMemory = 2 };

/// Reuse one instance serially. Default family tag36h11, 2 threads, decimation 2.
AFTagCore *AFTagCoreCreate(void);
void AFTagCoreDestroy(AFTagCore *core);
/// Input is borrowed for this call only. Output coordinates remain in the
/// original grayscale image pixels despite internal quad decimation.
/// On success, free *detections with AFTagCoreFreeDetections (NULL is allowed).
int AFTagCoreDetect(AFTagCore *core, const uint8_t *gray8, int width, int height,
                    int stride, AFTagDetection **detections, size_t *count);
void AFTagCoreFreeDetections(AFTagDetection *detections);
const char *AFTagCoreUpstreamRevision(void);

#ifdef __cplusplus
}
#endif
#endif
