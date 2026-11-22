# AprilTag AR physical testing checklist

The active task is the **Milestone 0 phone MVP field capture**. The developer builds and installs the capture app; the tester uses it on a real field and returns the recordings for review here. M0 cannot finish until that data has been received, opened, and reviewed with the user. No synthetic dataset, constructed test rig, surveyed fixture, BLE meter, or competitor comparison is required.

Only T0 below is active for this phase. T1 onward is a provisional later checklist to revise together after the first real-data review; do not execute it as a prerequisite for the MVP.

Record device/firmware, app revision, settings, procedure, results, and a capture-bundle reference for every completed item. Share the bundle and notes with the developer; the tester does not need to maintain application code. A developer may update these checkboxes from the tester's evidence. Use `passed`, `failed`, `pending`, or `not applicable` per result; an unperformed hardware test is not a pass.

## T0 Capture real field data for the phone MVP

**When:** The developer completes the installation and short export check in M0.1–M0.8. **Purpose:** Discover actual ARKit/LiDAR behavior and bring inspectable data back here to inform the next plan.

- [ ] **T0.1** Install/open the MVP on the actual LiDAR-capable iPhone. Confirm live imagery, tracking/depth status, live AprilTag IDs and corner outlines on a known `tag36h11` tag, recording controls, measurement probe, and export. Check that the ID is correct and that the outline clears when the tag leaves the view. Record device/OS/app versions and chosen capture settings. A short local check prevents an unusable field trip.
- [ ] **T0.1a** Verify the compact tag debug overlay and its **Details/Collapse** control: expanding must not crop/resize the camera or shift tag outlines, and taps outside the button must still select a tag. With the configured physical width, inspect translation/RPY, pose Z/range, center and neighborhood LiDAR depth, pixel reprojection error, angles, mismatch colors and validity reasons. Try an off-center tag, a tilted tag and missing depth; missing/low-confidence input must not show green agreement. Confirm the actual rate and age remain usable during a walk. Test manual width override and **Measure tag width with AR**; the estimate must change the solver only after **Use width**. Record the chosen thresholds and any observed lag.
- [ ] **T0.1b** Toggle **Show pose axes**, apply, and confirm red X / green Y / blue Z follow the detected tag while moving the phone. Toggle off and check the axes disappear. Check a rotated/tilted tag and tag disappearance; stale axes must clear with the outline. The gizmo represents tag-local coordinates, with half-tag-width axes, not gravity or field axes.
- [ ] **T0.1c** Tap the header version to open release notes. Record the version/build, full commit and UTC build date. Confirm a new session's `manifest.json.application` and recording-start event match that build identity; an older recording must retain its original identity after an app update.
- [ ] **T0.1d** Try 1×, 2× and 4×, then pinch between them. Confirm the View label follows the factor, tag corners/axes stay on the same image features, and the readout keeps its size. In Measure mode, select the same physical feature at different zoom factors; taps must map to the corresponding original-image depth sample. Return to 1× to compare. Verify presets still match the view after switching modes/tabs and confirm the recording retains original sensor imagery.
- [ ] **T0.1e** In **Measure**, turn **Floor on**, choose **Set floor**, and tap the actual floor polygon (horizontal surfaces can also be tables). Choose **Floor height**, tap a tag center/target surface, and move around: the floor-to-target vertical vector and label should stay on the original points. Take several two-point and height measurements, try zoom, hide/show the floor, and confirm **Clear** removes vectors but keeps the chosen floor. Brief limited tracking should hide overlays and restore them on recovery; backgrounding/reset must clear live placement. Start a recording after taking a measurement and check its start snapshot, then take another during recording and export. The saved geometry remains inspectable, but this version does not restore AR placement after app restart. Record any drift and compare a convenient known height without treating it as a required fixture.
- [ ] **T0.1f** Select the actual floor once, return to **Tag debug**, and point at tags at different heights. Confirm a height appears beside every visible ID without tapping each tag, and the selected tag's panel identifies **LiDAR** or **Pose** as its source. Move/tilt the phone and compare with an available reference height. Check missing floor, weak depth, stale/lost tracking and reset: a missing/invalid height must never become a plausible zero, and live heights must disappear or become unavailable. Record/export a short session and return it for height/provenance review.
- [ ] **T0.1g** Check tag labels, the selected-tag readout and a manual floor height in centimeters with feet/inches in parentheses. Open **Settings → Show English units**, switch it off and Apply: heights should show centimeters only. Cancel an unsaved toggle, reopen Settings, and relaunch the app to check persistence. Re-select the floor after relaunch as usual. A units change must not change the stored meter values or the configured tag width.
- [ ] **T0.1h** View several tags together: each should show its floor height, LiDAR camera range and tag-geometry camera range in a compact card. Check off-center tags, overlap/edge placement, missing depth, English-units on/off and tag disappearance. Select a card or outline, open Details, then collapse: the compact panel should leave most of the camera available. Camera ranges should remain separate from optical-axis depth Z. Record any label crowding or mismatch for review.
- [ ] **T0.2** Use the existing real field and its AprilTags. Record a walk past multiple tags, views of the floor and nearby structures, closer/farther views, brief stationary holds, and ordinary turns/movement. Return toward the starting area so we can inspect tracking consistency. No special fixture or independently surveyed field is required.
- [ ] **T0.3** During the session, make a few point/distance/vertical-difference measurements and bookmarks. Note tag IDs, what each measurement targeted, lighting, surfaces, and observed tracking/depth problems. Add a tape/reference value only if readily available, and distinguish it from the phone's estimate; it is not a gate requirement.
- [ ] **T0.4** Stop and save the session, then export the full bundle through Files/Share/AirDrop and bring it back here with notes. Preserve the original numeric depth/confidence files, RGB media, and timestamps/metadata. Verify the copied files are present before deleting anything from the phone.
- [ ] **T0.5** Confirm with the developer that the returned RGB is viewable, depth/confidence is decodable, sample frames, AprilTag detections and measurements can be matched, and missing/dropped data are identifiable. Repeat the field capture if the first export is unusable or missing the essential streams; diagnose the recorder before a repeat visit.
- [ ] **T0.G** At least one usable real-field recording has been received and inspected here, and the user has reviewed the findings and next priorities with us. The following plan is revised together before later milestone work begins. This gate proves usable acquisition, not final calibration accuracy.

## Later testing ideas awaiting the Milestone 0 review

The remaining tasks are retained for later planning. Their order, required devices, reference measurements, and acceptance criteria will be decided using the M0 data; none is a prerequisite for the initial field capture.

## T1 Capture the first reusable device dataset

**When:** Revisit after the M0 review if broader device/acquisition testing is needed. The initial real-field dataset is already required by T0; these are possible follow-on checks.

- [ ] **T1.1** Install the build on a physical iPhone. Check camera permissions, actual frame delivery, image orientation, overlay alignment, tracking state, start/stop, and recovery after backgrounding/navigation. If VisionCamera remains included, check camera ownership and mode handoff.
- [ ] **T1.2** On the LiDAR phone, verify actual depth/confidence capture and RGB/frame association. Record stationary and moving views, valid and missing depth, and several floor/tag-plane views. On the non-LiDAR phone, verify the visual-only fallback.
- [ ] **T1.3** Export a short clean session and at least one problematic session through the app's diagnostic exporter. Send both with layout/reference data and reproduction notes. Keep original numeric depth/confidence data when testing depth; a colored depth video alone is insufficient for the application's quantitative replay.
- [ ] **T1.4** Run a 15-minute live session and return timing, dropped-frame, tracking, memory, and thermal observations. The developer uses this evidence to distinguish actual device behavior from desktop replay performance.

## T2 Validate field calibration and LiDAR benefit

**When:** Revisit after the M0 review, when inspection/calibration features are ready and we are prepared to make accuracy claims.

- [ ] **T2.0** If agreed in the revised plan, prepare independently measured tag centers/orientations, a floor datum, known control, and uncertainty records. A stable small fixture may be useful at this later stage. Set the physical acceptance matrix and LiDAR-benefit criteria, and separate development/tuning captures from untouched final acceptance data.
- [ ] **T2.1** Capture the fixture and representative field using the documented route. Include known placement faults, unreadable/unknown tags, sparse coverage, and deliberate tracking interruptions. Record independently measured changes and the expected tag inventory.
- [ ] **T2.2** Repeat captures to measure repeatability and record setup time, walking time, physical-measurement time, and sufficiently observed coverage. For release qualification, include two operators and repeated runs on both device classes where the mode is supported; use the matrix agreed in T2.0.
- [ ] **T2.3** Supply development captures with measured heights/ranges and clearly separate truth from solver inputs. Keep final acceptance captures reserved as defined in T2.0. Let the developer's runner compare visual/VIO inputs, added depth constraints, added physical measurements, and both additions from the same saved capture. Four solver configurations do not require four new field walks. This comparison does not prove ARKit's internal LiDAR use was disabled.
- [ ] **T2.4** Check local height, tag-center and orientation errors, false passes, unresolved tags, and LiDAR benefit against independent measurements. Include reflective/dark surfaces, oblique views, depth holes, backing-surface offsets, and tag edges. Report conditions where adding depth improves or worsens results.
- [ ] **T2.5** Optionally run PractiCal and WPIcal on the same measured fixture using each tool's appropriate workflow. Record setup effort, coverage, accuracy, and repeatability. This provides context; it is not required before the developer starts coding and agreement between tools is not independent truth.

## T3 Verify the real BLE meter

**When:** M6 supplies the actual vendor driver. Scripted-provider tests have already been performed by the developer.

- [ ] **T3.1** Connect the meter directly to the custom app offline. Verify real units, datum, offsets/relative zero, live versus saved readings, button events, firmware behavior, and any missing metadata that requires operator entry.
- [ ] **T3.2** Record 100 controlled capture events including repeated identical lengths, disconnects, reconnection, power cycles, and unit/datum changes. Confirm each accepted reading is associated with the intended endpoints exactly once, and report lost/unavailable events honestly.
- [ ] **T3.3** Compare manual entry and BLE entry of the same independently measured lengths/heights. Check practical handling, sag/hook/housing references, and operator time. Export real device traces and failures so the developer can add them to the automated replay suite.

## T4 Verify the robot-camera comparison

**When:** M7/M8 provide the diagnostic workflows.

- [ ] **T4.1** Obtain the actual camera calibration/profile, robot-to-camera transform, field-map version, and stationary camera images/results. Measure a repeatable phone-to-camera alignment or use a stable jig; record its uncertainty.
- [ ] **T4.2** Compare expected and actual tag IDs, image corners, transforms, and robot poses. Distinguish approximate handheld results from quantitative aligned results. Verify the real telemetry connection; use moving-camera comparisons only when timing is sufficiently understood.
- [ ] **T4.3** Capture representative failures, including incorrect layout, size, mounting transform, or timing when practical. Export the original records and notes; the developer reproduces and diagnoses them through the synthetic/replay tools.

## T5 Accept the iOS release

**When:** M9 delivers the candidate. This is a product-release gate, separate from code completion.

- [ ] **T5.1** Run the agreed device/field matrix, including a 30-minute live session for battery, thermal behavior, storage growth, actual capture latency, interruptions, and recovery. Reuse earlier valid results when the relevant code/configuration is unchanged; retest affected areas after fixes.
- [ ] **T5.2** Have an operator complete setup, scanning, physical measurement, review, and export using the written instructions. Check exports in the intended robot consumer and confirm offline operation, unresolved-result handling, and diagnostic sharing.
- [ ] **T5.3** Record pass/fail/pending for the proposed accuracy, coverage, responsiveness, and LiDAR-benefit claims. Approve only the device/condition/quantity combinations supported by evidence. A failed required claim needs a fix or an explicitly agreed scope revision followed by retesting.
- [ ] **T5.G** Required physical and usability checks pass, serious defects are resolved, and the owner accepts the supported operating envelope. Only then is the candidate eligible for public release with those accuracy claims.

## T6 Accept Android hardware support

**When:** M10 supplies an Android candidate. No Android hardware preparation is required to start the iOS development work.

- [ ] **T6.1** Repeat camera, ARCore tracking, permissions, lifecycle, telemetry, and real BLE checks on each initially supported Android model. Record whether depth is derived from motion, hardware sensors, or fused sources.
- [ ] **T6.2** Repeat the applicable independent accuracy and live-performance checks. Do not transfer an iPhone LiDAR accuracy claim to Android without evidence. Return capture bundles for failures.
- [ ] **T6.G** Required Android checks pass and the owner accepts the supported device/condition matrix before public release.

## Data to return to the developer

The M0 app's exporter creates one self-contained bundle that can be inspected outside the phone. Start with a documented, simple manifest and original data; refine the long-term schema after reviewing the first real-field recordings. The tester should not assemble low-level files manually.

| Bundle content | Purpose |
| --- | --- |
| Manifest | App/core revision, settings, device/OS/firmware, session ID, capabilities, and file checksums. |
| RGB frames and camera metadata | Original selected images, image dimensions/intrinsics, frame IDs, capture timestamps/clock domain, recorded pose, orientation, and tracking state. |
| Numeric depth/confidence records | Original selected buffers, resolution, units/convention, smoothing/source information, frame association, and mapping metadata. |
| Measurements and events | Endpoints, datum, units, uncertainty, original device data when available, confirmations, interruptions, resets, and timing. |
| Optional field/reference information | Include an available field layout and any convenient reference measurements with their source. Independent survey/held-out truth is optional in M0 and may be added for later accuracy work. An app-estimated pose is not physical ground truth. |
| Notes and expected result | Steps, what looked wrong, conditions, approximate event/frame/time, and supporting photos if useful. |

Record once, then let the developer replay the same evidence for most code iterations. Capture again when a fix changes acquisition itself, a new physical condition must be tested, or the existing data cannot answer the question.
