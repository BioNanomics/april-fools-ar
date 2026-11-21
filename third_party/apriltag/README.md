# Vendored AprilTag 3 production subset

- Authoritative upstream: <https://github.com/AprilRobotics/apriltag>
- Exact commit: [`b7c0ebe9aa20f82ec7a828579004f9e706bfecd9`](https://github.com/AprilRobotics/apriltag/commit/b7c0ebe9aa20f82ec7a828579004f9e706bfecd9), August 7, 2026; upstream CMake project version 3.4.5.
- Retrieved November 20, 2026 from the upstream Git repository. `REVISION` records the pin.
- Retained source files are **unmodified**. Subset: core detector/quad/pose C and headers, `tag36h11` only, and upstream `common/` production utilities. The pose implementation is retained as an upstream library component but is not exposed by this increment's app wrapper.
- No examples, upstream tests, generated family variants, ArUco families, Python wrapper, nested Git metadata, downloads or build artifacts are vendored.

`sources.txt` is the exact production C compilation list, relative to this folder. It corresponds to upstream CMake's `APRILTAG_SRCS` + `COMMON_SRC`, with only the required `tag36h11` family selected. All header includes preserve the upstream `common/` hierarchy. Apple uses its system pthread and math implementations; no OpenCV or other package is required.

## Licenses and binary notices

The principal project and common files carry the Regents of the University of Michigan's BSD 2-Clause terms, retained in **[LICENSE.md](LICENSE.md)** and every source header. `common/image_u8_parallel.c/.h` contain an additional 2025–2026 Regents copyright with the same terms.

`common/pthreads_cross.c/.h` carry John Schember's **MIT** notice. They are included by the upstream library build (the Windows replacement implementation is conditionally compiled). Their complete copyright/permission/disclaimer is retained in their headers and reproduced in **[NOTICE.md](NOTICE.md)** alongside the main BSD notice. The remaining retained `common/getopt`/image/JPEG utilities carry the Regents BSD headers; no extra zlib or system getopt source was downloaded.

Ship `LICENSE.md` and `NOTICE.md` with app-distribution materials/resources. This repository's app-specific wrapper/core adapters are separate from the unmodified upstream source. Upstream identity/license is not a claim of official iOS support or measured field accuracy.

To update: inspect a new upstream revision, copy the same production subset while preserving headers, update `REVISION`, `sources.txt`, notices and the revision constant in `native/AprilTag/AFTagCore.c`, then rerun the genuine-tag smoke test and iOS build/device checks. Do not silently follow a floating branch.
