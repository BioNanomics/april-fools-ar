# M0 live AprilTag detection

Live AprilTag identification is required for Milestone 0. The new build adds the shared C detector, the iOS adapter, native outlines, visible IDs and frame-associated detection records. The original field capture and joint-review gate remains open.

## Implementation

- AprilTag 3.4.5, upstream revision `b7c0ebe9aa20f82ec7a828579004f9e706bfecd9`, vendored unmodified with an explicit production source list and BSD/MIT notices.
- `AFTagCore` accepts grayscale pixels, dimensions and row stride with no Apple dependency. The iOS adapter reads ARKit's Y plane and also supports 8-bit grayscale/BGRA.
- `tag36h11`, two detector threads, decimation 2, edge refinement, up to two corrected bits.
- One analysis in flight, targeting 8 Hz, independent of recording and depth. Old results and outlines expire after 0.5 seconds.
- UI shows visible IDs, analysis count and latency. Native outlines use the source frame's image-to-display transform.
- `aprilTagDetections` events contain source frame/segment/timestamp, geometry, IDs/corners/quality, latency, failures and skipped-analysis counters. Empty successful results are distinct from analysis failures. Positive detections request a bounded source JPEG snapshot.
- Late results cannot enter a different recording or append to a finalized session. The manifest records the detector revision, configuration and session counts.
- No tag size is assumed and no tag pose, placement accuracy or complete field coverage is claimed.

## Validation completed

1. `sh native/AprilTag/tests/run-smoke.sh`: passed. The actual shared detector decodes upstream-rendered tag 42 at center `(230, 180)` in a padded-stride image; checks family, corrected bits, corner bounds and full-resolution coordinates; blank image returns zero; invalid stride is rejected.
2. Local C warnings-as-errors and Objective-C ARC syntax checks passed. The host image check is a parser/unit test, not a physical-camera accuracy test.
3. `npx tsc --noEmit`, `npm run lint -- --quiet`, and all three Jest tests passed. The new UI test verifies current tag IDs appear before recording and clear when absent.
4. Signed iOS Release build 2 passed. `codesign --verify --deep --strict` passed; license and notice files are present in the app bundle.
5. Installed through Device Hub and launched on Doug's iPhone 17 Pro. The native pipeline reported `Looking for tags`, 51 analyzed frames and approximately 6 ms analysis time in the observed screen. This establishes live frame delivery and detector execution.

## Physical validation still required

The phone still showed a black RGB preview, ARKit `LIMITED / initializing`, and `DEPTH WAITING`. The separate voice/video overlay was left untouched; its presence alone does not establish the cause. No physical tag was decoded and no live recording/export was completed in this run.

- [ ] With the rear camera free and pointed at a well-lit scene, verify RGB and depth.
- [ ] Present a known `tag36h11` tag: verify its ID, outline alignment and clearing when removed.
- [ ] Record a short tag/measurement/bookmark session and export the ZIP.
- [ ] Run `python3 scripts/inspect-session.py <zip> --require-tags` and inspect RGB, numeric depth/confidence and detection geometry.
- [ ] Complete the real-field capture and joint review in M0.9/M0.10/M0.G.

The full milestone is not complete until these physical checks and the field-review gate pass.
