#include "AFTagCore.h"
#include "apriltag.h"
#include "tag36h11.h"
#include <stdlib.h>
#include <string.h>

struct AFTagCore {
    apriltag_detector_t *detector;
    apriltag_family_t *family;
};

AFTagCore *AFTagCoreCreate(void) {
    AFTagCore *core = calloc(1, sizeof(*core));
    if (!core) return NULL;
    core->family = tag36h11_create();
    core->detector = apriltag_detector_create();
    if (!core->family || !core->detector) { AFTagCoreDestroy(core); return NULL; }
    core->detector->nthreads = 2;
    core->detector->quad_decimate = 2.0f;
    core->detector->refine_edges = true;
    apriltag_detector_add_family_bits(core->detector, core->family, 2);
    return core;
}

void AFTagCoreDestroy(AFTagCore *core) {
    if (!core) return;
    if (core->detector) apriltag_detector_destroy(core->detector);
    if (core->family) tag36h11_destroy(core->family);
    free(core);
}

int AFTagCoreDetect(AFTagCore *core, const uint8_t *gray8, int width, int height,
                    int stride, AFTagDetection **detections, size_t *count) {
    if (detections) *detections = NULL;
    if (count) *count = 0;
    if (!core || !gray8 || !detections || !count || width < 4 || height < 4 || stride < width)
        return AFTagCoreInvalidInput;
    image_u8_t image = { .width = width, .height = height, .stride = stride, .buf = (uint8_t *)gray8 };
    zarray_t *found = apriltag_detector_detect(core->detector, &image);
    if (!found) return AFTagCoreOutOfMemory;
    size_t n = (size_t)zarray_size(found);
    AFTagDetection *output = n ? calloc(n, sizeof(*output)) : NULL;
    if (n && !output) { apriltag_detections_destroy(found); return AFTagCoreOutOfMemory; }
    for (size_t i = 0; i < n; i++) {
        apriltag_detection_t *tag = NULL;
        zarray_get(found, (int)i, &tag);
        output[i].id = tag->id;
        output[i].hamming = tag->hamming;
        output[i].decisionMargin = tag->decision_margin;
        strncpy(output[i].family, "tag36h11", sizeof(output[i].family) - 1);
        memcpy(output[i].center, tag->c, sizeof(output[i].center));
        memcpy(output[i].corners, tag->p, sizeof(output[i].corners));
    }
    apriltag_detections_destroy(found);
    *detections = output;
    *count = n;
    return AFTagCoreSuccess;
}

void AFTagCoreFreeDetections(AFTagDetection *detections) { free(detections); }
const char *AFTagCoreUpstreamRevision(void) { return "b7c0ebe9aa20f82ec7a828579004f9e706bfecd9"; }
