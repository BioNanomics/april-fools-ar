#include "AFTagCore.h"
#include "apriltag.h"
#include "tag36h11.h"
#include "common/image_u8.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    const int width = 480, height = 400, stride = 512, scale = 20, x0 = 130, y0 = 80;
    uint8_t *pixels = malloc((size_t)stride * height);
    assert(pixels);
    memset(pixels, 255, (size_t)stride * height);
    AFTagCore *core = AFTagCoreCreate();
    assert(core);
    AFTagDetection *found = NULL;
    size_t count = 123;
    assert(AFTagCoreDetect(core, pixels, width, height, stride, &found, &count) == AFTagCoreSuccess);
    assert(count == 0 && found == NULL);
    apriltag_family_t *family = tag36h11_create();
    image_u8_t *tag = apriltag_to_image(family, 42);
    assert(tag);
    for (int y = 0; y < tag->height; y++) for (int x = 0; x < tag->width; x++)
        for (int dy = 0; dy < scale; dy++) for (int dx = 0; dx < scale; dx++)
            pixels[(y0 + y * scale + dy) * stride + x0 + x * scale + dx] = tag->buf[y * tag->stride + x];
    assert(AFTagCoreDetect(core, pixels, width, height, stride, &found, &count) == AFTagCoreSuccess);
    assert(count == 1 && found[0].id == 42 && found[0].hamming == 0);
    assert(strcmp(found[0].family, "tag36h11") == 0 && found[0].decisionMargin > 0);
    // Confirms internal decimation has not halved the returned pixel coordinates.
    assert(fabs(found[0].center[0] - (x0 + tag->width * scale / 2.0)) < 2);
    assert(fabs(found[0].center[1] - (y0 + tag->height * scale / 2.0)) < 2);
    for (int i = 0; i < 4; i++) {
        assert(found[0].corners[i][0] > x0 && found[0].corners[i][0] < x0 + tag->width * scale);
        assert(found[0].corners[i][1] > y0 && found[0].corners[i][1] < y0 + tag->height * scale);
    }
    printf("PASS tag36h11 ID=%d center=(%.2f,%.2f), padded stride=%d; blank zero; upstream=%s\n",
           found[0].id, found[0].center[0], found[0].center[1], stride, AFTagCoreUpstreamRevision());
    AFTagCoreFreeDetections(found);
    assert(AFTagCoreDetect(core, pixels, width, height, width - 1, &found, &count) == AFTagCoreInvalidInput);
    image_u8_destroy(tag); tag36h11_destroy(family); AFTagCoreDestroy(core); free(pixels);
    return 0;
}
