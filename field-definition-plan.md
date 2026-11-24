# Field definitions, AR placement, and walk inventory

Planning review: November 23, 2026. Current delivery scope: the phone app on FRC 2026 and FTC 2025–2026/2026–2027 fields. Robot consumers, FRC 2027 import and richer visual layers are deferred until much later. The user authorized FD.1–FD.4 implementation and a phone handoff on November 24, 2026. Their software checklists below are complete with linked evidence; physical field acceptance remains FD.6.

Build a versioned, offline field package for the phone while preserving a format and portable core that robots can consume later. YAML is the default for our committed field specifications, normalized database/app storage and field-definition display; all tools we maintain must also support JSON. Keep the geometry and estimation in the existing portable C++ core, importing published field data without requiring robot consumers now. The phone should draw expected tag locations in the room after field registration and save a list of the tags actually seen during each walk, including their published positions and any separately estimated positions.

## 1. Season and program scope

Use explicit program and season identities rather than a bare year or whichever layout a library calls “current.” FTC seasons span two calendar years.

| Program / season | Initial support and source availability |
| --- | --- |
| FRC 2026 REBUILT | Support both official welded and AndyMark layouts. Each has tags 1–32, but their geometry differs. Welded is 16.541 × 8.069 m; AndyMark is 16.518 × 8.043 m. [Official layouts: welded](https://github.com/wpilibsuite/allwpilib/blob/v2026.2.2/apriltag/src/main/native/resources/edu/wpi/first/apriltag/2026-rebuilt-welded.json), [AndyMark](https://github.com/wpilibsuite/allwpilib/blob/v2026.2.2/apriltag/src/main/native/resources/edu/wpi/first/apriltag/2026-rebuilt-andymark.json). |
| FRC 2027 | Deferred beyond the current delivery scope, even after official geometry is published. No 2027-season layout exists in the checked WPILib 2027 alpha-8 field catalog; its default is still 2026 REBUILT welded. The software version does not identify the field season. [Pinned catalog](https://github.com/wpilibsuite/allwpilib/blob/v2027.0.0-alpha-8/fields/src/generated/main/java/org/wpilib/fields/Fields.java). |
| FTC 2025–2026 DECODE | Import the SDK's game-specific library. Distinguish fixed localization targets from Obelisk tags that must not be used as global anchors. [SDK release notes](https://github.com/FIRST-Tech-Challenge/FtcRobotController#version-110-20250827-105138), [official archived season](https://ftc-resources.firstinspires.org/ftc/archive/2026/game). |
| FTC 2026–2027 BIOBUZZ | Already published at this review date. Support its tag/cluster definitions and moving-target observations. Do not assign permanent field poses to moving clusters. [Official season materials](https://ftc-resources.firstinspires.org/ftc/game?hsLang=en), [SDK 12 release notes](https://github.com/FIRST-Tech-Challenge/FtcRobotController#version-120-20260907-090034). |

The first end-to-end fixed-field example should be FRC 2026. Include FTC DECODE and BIOBUZZ in the data contract and validation from the start so that fixed tag positions do not become a hidden assumption.

## 2. What is available and reusable

### This application

The original review used the working tree, including existing in-progress changes, against base commit `3fff60893f27da487f2de198661d9ea20daa3256`. This plan also incorporates the field/year and Auto sizing merged into [main at `5f46165ff300034ed1ffbdde3701103d252d007f`](https://github.com/BioNanomics/april-fools-ar/commit/5f46165ff300034ed1ffbdde3701103d252d007f).

| Existing component | Reuse | Work still needed |
| --- | --- | --- |
| [Portable spatial core](native/SpatialCore/README.md), [architecture decision](docs/decisions/003-shared-spatial-core.md) | C++17 behind C ABI; Swift, C++, Java/JNI and Android consumers; geometry, pose calculations and projection. | Field definitions, explicit field frames, registration, field-relative estimates and observation summaries. |
| [AprilTag core](native/AprilTag/README.md), `AFTagCore.h/.c` | Actual `tag36h11` detector, ordered corners, metric pose, ambiguity and reprojection diagnostics. The current pipeline solves at a reference size and then resolves/rescales each detection; the corner solver also remains available. | Move the existing per-detection size policy into the shared core and source its catalog from YAML; add package membership and conflict handling. |
| [Current sizing implementation](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/native/ARCapture/TagDebugMath.swift#L11), [settings UI](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/DebugSettingsModal.tsx#L112) | `TagFieldCatalog`, Auto/FTC/FRC/Custom modes, field/year presets, per-ID mixed-size mapping, LiDAR inference, settings migration and recorded resolution evidence. | Replace duplicated Swift/TypeScript size tables with shared YAML-backed data and preserve current phone behavior, with a neutral contract for later robot adapters. These are size definitions, not field poses. |
| [AR coordinator](native/ARCapture/ARCaptureCoordinator.swift) | Source-frame camera pose/intrinsics, bounded asynchronous detection, native event recording, tracking and coordinate-segment lifetime. | Attach field identity and registration to the matching source observation; maintain walk state independently of short-lived live outlines. |
| [Projection adapter](native/ARCapture/SpatialProjection.swift), [world overlay](native/ARCapture/SpatialMeasurementOverlayView.swift) | Project world points, segments and polygons with clipping, orientation and preview zoom. | Draw expected tag planes/IDs/normals from field geometry; no full field mesh is necessary for this first overlay. |
| [Observed tag overlay](native/ARCapture/AprilTagOverlayView.swift) | Current image-space detection outlines and selection. | Keep their meaning distinct from predicted field placements. They currently expire after 0.4 seconds. |
| [Gravity orientation](native/ARCapture/TagGravityOrientation.swift), [floor height](native/ARCapture/TagFloorHeight.swift) | Matching-frame gravity-relative tag tilt/printed-up geometry and center height above an operator-confirmed floor, with explicit source/availability. | Compare against the selected definition before accepting a first-tag anchor; retain the independent floor datum and explain expected/observed differences. |
| [Capture format](docs/capture-format.md), [MP4 format](recording-format/FORMAT.md) | Raw detections, frame/segment identity, source transforms, metadata and exact sidecar-file transport. | Package snapshots, registration events, walk summary and playback handling for the new state. |
| [Robot examples](robot/README.md), [Android binding](bindings/android/README.md) | Shared numerical code and packaging foundations. | Real FRC/FTC field consumers and camera adapters. Existing examples do not implement robot localization. |

Use raw detections for estimation and records. The current `TagReadoutFilter.swift` smooths presentation copies; its outputs must not become registration inputs or measurement evidence.

### Existing Auto size logic to preserve and reuse

Auto means **physical-width inference**, separate from selecting a field package. A tag's family/ID or inferred size does not identify its competition, season, variant, field origin or surveyed position. In particular, FRC and FTC DECODE share the 0.1651 m size. Keep these as separate concepts in the app and the data contract. [Current recorded contract](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/docs/capture-format.md#L52).

The existing modes are `auto`, `ftc`, `frc` and `custom`. Fresh settings use Auto with year `0`; explicit FTC defaults to ending-year 2027 and FRC to calendar-year 2026. The catalog also supports FTC ending-years 2024–2026 and FRC 2024–2025. Preserve those older **size-only** presets without treating them as complete field-layout packages or requiring their full geometry in this initial scope. CENTERSTAGE maps IDs 7/10 to 0.127 m and IDs 1–6/8/9 to 0.0508 m; other IDs leave metric pose unavailable. Other explicit, single-size seasons apply the selected size even to practice IDs, so size selection alone is not field-membership validation. [Catalog and settings](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/native/ARCapture/TagDebugMath.swift#L11).

For each observation, `TagDebugMath.resolveTagSize` uses the matching source frame:

```text
estimatedEdge = referenceEdge × centerLiDAR_Z / referencePose_Z
scale = selectedNominalEdge / referenceEdge
```

In Auto mode, resolution requires normal tracking, confidence-category-2 center LiDAR, positive finite depth, an unambiguous reference pose, positive decision margin, zero corrected bits and passing configured reprojection/incidence/range gates. Explicit preset/custom sizing does not require those Auto inputs; downstream pose usability has its own gates. A neighboring depth sample does not replace an unusable center. Accept exactly one matching standard:

| Nominal edge | Current relative tolerance |
| --- | --- |
| 0.0508, 0.08255, 0.1016, 0.127 m | 10% for each candidate |
| 0.1524, 0.1651 m | 3% for each candidate, keeping 6-inch sample and 6.5-inch field prints distinct |

Retain the continuous estimate as evidence and apply the selected nominal width. If resolution fails, preserve the ID/corners and explicit unavailable reason, without a metric pose or silent fallback to the reference width. Selection is per observation, so the same ID can be observed at different physical sizes. [Resolver](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/native/ARCapture/TagDebugMath.swift#L211).

Reuse `rescaledPose`: translation/range and candidate translation separation scale linearly; object-space pose errors scale by `scale²`; rotation, pixel reprojection, error ratio, ambiguity and angular quantities retain their meaning. Resolution currently runs before quality, ranges, gravity and floor-height enrichment. Preserve that ordering and metric consistency when extracting the calculation into AFSC, rather than implementing a second sizing algorithm. [Rescaling](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/native/ARCapture/TagDebugMath.swift#L296), [capture integration](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/native/ARCapture/ARCaptureCoordinator.swift#L825).

Preserve `tagSizeResolution` status/source/reason, mode and explicit year or null, selected width, estimated edge, reference width, matching-frame depth/confidence and applied tolerance. The authoritative applied scale is `pose.tagSizeMeters`/`pose.tagSizeSource`; `debugSettings.tagSizeMeters` is a reference scale in Auto/mixed-size modes. Keep Apply/Cancel behavior, full custom-width precision, manual/AR overrides and legacy migration: untouched old FRC defaults become Auto, while manual/AR widths remain Custom. Historical observations retain their original scale and evidence. [Settings regression tests](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/__tests__/TagSizeSettings.test.tsx), [native regression tests](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/native/ARCapture/tests/TagDebugMathTests.swift#L34).

LiDAR chose the scale in Auto, so subsequent pose-versus-LiDAR agreement is correlated evidence and cannot independently validate that size. The existing [validation record](https://github.com/BioNanomics/april-fools-ar/blob/5f46165ff300034ed1ffbdde3701103d252d007f/docs/validation/M0-field-year-tag-sizes.md) reports automated checks and physical installation/settings display; physical Auto-size accuracy and physical native accessibility remain pending. This reuse does not complete the YAML, field-registration or walk-inventory milestones.

### Refinery ForceField

Reviewed [commit `dbdcbdfe013d8946f6af1fa485a3f357614ed50b`](https://github.com/BioNanomics/refinery-forcefield/tree/dbdcbdfe013d8946f6af1fa485a3f357614ed50b).

- Its [field manifest](https://github.com/BioNanomics/refinery-forcefield/blob/dbdcbdfe013d8946f6af1fa485a3f357614ed50b/editor/fields/manifest.json) contains FRC 2023–2026 image/calibration pairs. It has no AprilTag pose database, FTC catalog, or 3D field models.
- Reuse the catalog and calibrated image approach for a top-down expected/seen map. The [2026 image metadata](https://github.com/BioNanomics/refinery-forcefield/blob/dbdcbdfe013d8946f6af1fa485a3f357614ed50b/editor/fields/2026-rebuilt.json) specifies feet and image crop corners; it corresponds approximately to the welded dimensions. Do not apply that image calibration to AndyMark without checking it.
- The [editor](https://github.com/BioNanomics/refinery-forcefield/blob/dbdcbdfe013d8946f6af1fa485a3f357614ed50b/editor/editor.js) supplies field-to-canvas mapping, force arrows and heatmaps. Its approximate 2025 reef polygons are illustrative 2D obstacles, not authoritative tag geometry. Its loader assumes feet and rounds dimensions; our importer should honor declared units and preserve source precision.
- Its [preset format and robot code](https://github.com/BioNanomics/refinery-forcefield/blob/dbdcbdfe013d8946f6af1fa485a3f357614ed50b/README.md) describe driving-assist charges. Keep those as optional, separately identified artifacts. They do not contain the season/variant/tag metadata needed here, and force strength is not localization confidence.
- The README/build metadata say MIT, but the inspected tree has no standalone LICENSE file. Confirm code and image attribution/license terms before redistribution; this does not block designing the interfaces.

### Upstream field formats

**FRC:** Support both WPILib formats rather than treating one JSON schema as universal. The [2026 format](https://github.com/wpilibsuite/allwpilib/blob/v2026.2.2/apriltag/src/main/native/resources/edu/wpi/first/apriltag/2026-rebuilt-welded.json) uses `tags` and `field.{length,width}`. The [2027 alpha-8 integrated format](https://github.com/wpilibsuite/allwpilib/blob/v2027.0.0-alpha-8/fields/src/main/native/resources/org/wpilib/fields/frc/2026-rebuilt-welded.json) uses `name`, `season`, `game`, `program`, `field-dimensions`, optional `field-image` and `field-tags`. Both encode translation plus quaternion `W/X/Y/Z`; neither provides the detector family or physical tag edge. Record those separately from official season documentation. [WPILib tag introduction](https://docs.wpilib.org/en/latest/docs/software/vision-processing/apriltag/apriltag-intro.html).

**FTC:** Use game-specific `AprilTagGameDatabase` libraries and pinned official Vision artifacts. The [metadata](https://ftc-docs.firstinspires.org/en/latest/apriltag/vision_portal/apriltag_metadata/apriltag-metadata.html) includes per-tag size/units and optional field geometry. SDK 12 adds separate cluster metadata and member geometry; clusters have names rather than a printed tag ID. Preserve both collections. `addLibrary()` copies both; `addTags()` omits clusters, and `lookupTag(id)` does not find cluster members. [FTC library API](https://ftc-docs.firstinspires.org/en/latest/apriltag/vision_portal/apriltag_library/apriltag-library.html).

The [official Vision 12.0.0 source artifact](https://repo.maven.apache.org/maven2/org/firstinspires/ftc/Vision/12.0.0/Vision-12.0.0-sources.jar), especially `AprilTagGameDatabase`, shows DECODE fixed targets 20/24 at 6.5 inches and Obelisk IDs 21–23 without meaningful global placement. BIOBUZZ has four clusters with member IDs 30–45 at 3.25 inches. Some missing SDK field poses are represented by zero/identity defaults: non-null metadata is not sufficient to authorize localization. Import explicit placement/anchor semantics, never infer them from zero coordinates.

Initial physical geometry to verify during import:

| Dataset | Family | Pose-estimation edge | Static localization eligibility |
| --- | --- | --- | --- |
| FRC 2026 | `tag36h11` | 0.1651 m | Published fixed tags, subject to chosen field variant and observation quality. |
| FTC DECODE | `tag36h11` | 0.1651 m | Targets 20/24; exclude Obelisk 21–23. |
| FTC BIOBUZZ | `tag36h11` | 0.08255 m | Moving clusters are ineligible as stationary anchors. |

Keep pose-estimation edge separate from outer artwork size: the [DECODE manual](https://ftc-resources.firstinspires.org/ftc/archive/2026/game/manual) describes 8.125-inch artwork, while the SDK uses the 6.5-inch black edge. Use explicit game-specific factories, not `getCurrentGameTagLibrary()`, which changes with the SDK and also includes sample tags.

Research pins for reproducible implementation: WPILib `v2026.2.2`; WPILib `v2027.0.0-alpha-8` at `4817543253e343afcf2b630537e995d74d21db62`; [FTC SDK revision `e14c2aeb33e84d4ea21697beeea9ac49557be870`](https://github.com/FIRST-Tech-Challenge/FtcRobotController/tree/e14c2aeb33e84d4ea21697beeea9ac49557be870); Vision `12.0.0` source JAR SHA-256 `756294f8307da88b85a73c5a804dbc20f65dd60af97534ed3dea8f38e528aba8`. Recheck upstream releases when implementation begins without changing historical recording identities.

WPILib alpha-8 also includes [FTC DECODE imagery](https://github.com/wpilibsuite/allwpilib/blob/v2027.0.0-alpha-8/fields/src/main/native/resources/org/wpilib/fields/ftc/2025-2026-decode.json), but no tag poses for that entry. Image extents are a visualization calibration, not a substitute for FTC geometry.

## 3. Shared field-package contract

Start with small, versioned YAML files and an in-memory ID index; a database server is unnecessary. Commit our field definitions as `.yaml`. Accept both YAML and JSON on import, validate them against the same logical schema, and convert accepted input into our normalized YAML representation. Make the published reference immutable and keep observed/candidate geometry separate.

Proposed package contents:

| Artifact | Required meaning |
| --- | --- |
| `manifest.yaml` | Schema version; program; explicit season start/end; game; field variant; package ID/revision; source URLs, versions and SHA-256 hashes; license attribution; frame definitions; units; asset references and capability status. |
| `tags.yaml` | Physical tag records keyed by family/ID within this package: name, detected edge in meters, tag-frame convention, placement type, optional reference pose and provenance, localization eligibility, parent/cluster identity. |
| `clusters.yaml` when applicable | Named targets with member IDs, each member's rigid transform into the cluster frame, aiming origin and orientation, motion semantics and optional valid field placement. Aiming origin and printed tag center are separate. |
| Shared `size-standards.yaml` | YAML-backed catalog of nominal widths, source references, explicit season/per-ID size rules and Auto candidate tolerances. Generate or load matching data for the current phone/host tools; preserve a neutral format for future robot consumers. Size-only catalog entries need not have field poses. |
| Source provenance | Original source format, URL/revision and byte hash; reproducible conversion instructions. Any retained original bytes are labeled source evidence, while the working field definition is YAML. |
| Optional map/assets | Image, crop corners, units and explicit image-to-field transform; later geometry/force presets with their own provenance. |

Use meters, radians and explicitly ordered quaternion `[w,x,y,z]` in normalized files. Retain source frame definitions and provenance alongside normalized values. Use double precision in geometry. Matrices passed through AFSC remain column-major `T_destination_source`.

### YAML default and JSON compatibility

All field-definition tools we maintain—importers, validators, editors, phone loaders, robot adapters, replay utilities and viewers—must accept YAML and JSON with equivalent meaning as each tool is implemented. Current milestones cover phone/host tools; building robot adapters remains deferred. Default saves/exports and human-readable display to YAML, with explicit JSON import/export available. This is a serialization choice around one data model; keep format conversion outside the numerical core.

Persist normalized field definitions as UTF-8 YAML on app disk and, if a database is used, as YAML document text with schema/package identity and hashes. Indexed metadata or tag lookups may be derived from it. Show field definitions as formatted YAML in the UI and debugging views. Convert upstream JSON at ingestion; generate the required JSON when exchanging data with external consumers such as WPILib or PhotonVision. Their native readers do not gain YAML support automatically.

Specify a portable YAML 1.2 subset with string mapping keys, explicit scalar types, sequences and mappings. Reject duplicate keys, nonfinite geometry, custom executable tags, aliases/merge keys and excessive nesting/size. Quote season labels and other ambiguous text. Choose parser/serializer dependencies for current Swift and host tools, including licenses, while preserving a format future C++/Java adapters can consume. Define stable output ordering and numeric precision for reproducible YAML, with separate hashes for source bytes and normalized package bytes. Round-trip YAML and JSON through each implemented tool and compare semantic geometry and identities, including null/false/zero distinctions.

Field-definition serialization has its own contract; existing capture JSONL and MP4 metadata remain source observation/container formats. A YAML field-package snapshot and YAML summaries can travel as ordinary sidecars inside that container.

Distinguish at least `fixedField`, `movable`, `clusterMember`, and `unknown` placement semantics, with a separate `localizationEligible` flag. A cluster member's global pose is derived only when its parent's field pose is valid. Every pose declares its frame; unavailable global poses are null with a reason.

Keep selected field-package identity independent of size-selection mode and its legacy `competitionYear` setting. Auto/Custom year `0` means no season inferred by sizing; it must neither select a package nor erase one explicitly selected for the walk. Preserve that legacy setting at adapter boundaries and use explicit unavailable identity in normalized records. A practice ID can have a usable metric pose under an explicit single-size preset while remaining unknown to the selected field layout, with no invented nominal field position.

Use package sizes for expected tag geometry and the recorded per-detection resolution for observed geometry. Preserve the explicit mode's sizing policy; manual/AR overrides stay in session/observation state and do not rewrite published YAML. Record any discrepancy between applied/estimated width and the reference size visibly as an assumption/conflict. Do not silently replace one with the other or certify placement from it; changing a sizing policy invalidates affected live results/registration until rechecked. An inferred nominal width supplies no additional field-membership or localization eligibility.

Keep each program's official field convention as a named frame, with adapters into shared math. FRC keeps the fixed blue-origin, +Z-up WPILib frame. FTC keeps its official centered field frame and SDK orientation convention: origin on the mat's top surface, +Y away from the red wall, +X to the right when looking inward from that wall, +Z up. Preserve the season's alliance/audience orientation explicitly. Do not move FTC's origin to a blue corner implicitly. Store any common display-frame transform explicitly. Preserve the AR world as a separate +Y-up frame. [WPILib coordinates](https://docs.wpilib.org/en/stable/docs/software/advanced-controls/geometry/coordinate-systems.html), [FTC field coordinates](https://ftc-docs.firstinspires.org/en/latest/game_specific_resources/field_coordinate_system/field-coordinate-system.html).

Validation must reject duplicate physical identities, unsupported families, invalid size/units, nonfinite values, invalid rigid transforms and broken cluster membership. Check tag counts and known coordinates against pinned sources. Compare image dimensions to layout dimensions with a documented tolerance; report discrepancies rather than stretching authoritative tag positions. Tag centers may legitimately be outside the carpet bounds, so bounds checks need season-specific interpretation.

## 4. Geometry and field registration

Field geometry alone cannot place an overlay in an arbitrary AR session. Gravity supplies up, but not field origin or heading. Add a registration with the selected package hash, AR segment, transform, contributing observations/control, anchor assumptions, method/version, quality diagnostics and lifetime.

Use these explicit frames:

- `F`: selected program's field frame; `W`: current AR world.
- `A`: ARKit camera; `C`: optical camera, +X right/+Y down/+Z forward.
- `D`: raw detector tag, +X printed right/+Y down/+Z into print.
- `L`: the source layout's tag frame; `R`: robot body frame.

Compose only after checking both camera and tag basis conversions:

```text
T_W_C = T_W_A × diag(1, -1, -1, 1)
T_W_D_observed = T_W_C × T_C_D
T_F_D_reference = T_F_L × T_L_D

T_W_F_initial = T_W_D_observed × inverse(T_F_D_reference)
T_W_D_expected = T_W_F × T_F_D_reference
T_F_D_observed = inverse(T_W_F) × T_W_D_observed

T_F_C = T_F_D_reference × inverse(T_C_D)
T_F_R = T_F_C × inverse(T_R_C)
```

The final two equations require a valid fixed reference, calibrated camera mounting and a usable observation. The phone registration equations likewise cannot use a moving target as a stationary anchor.

`T_L_D` is source-specific. WPILib's outward-normal tag axis differs from the raw detector's into-print Z; its adapter maps detector coordinates to layout tag coordinates as `(x_L,y_L,z_L)=(-z_D,x_D,-y_D)`, with zero translation. The ARKit camera-axis conversion does not fix that difference. FTC's converted `ftcPose` axes also differ from raw optical pose. Specify and verify the exact basis matrices and printed corner order for each adapter using independently calculated examples. Do not build transformations from displayed Euler angles. [AprilRobotics conventions](https://github.com/AprilRobotics/apriltag#coordinate-system), [PhotonVision conventions](https://docs.photonvision.org/en/v2026.3.2/docs/apriltag-pipelines/coordinate-systems.html), [FTC pose](https://ftc-docs.firstinspires.org/en/latest/apriltag/vision_portal/apriltag_pose/apriltag-pose.html).

### First-tag anchor and height/tilt warnings

Propose the **first eligible tag seen** as the initial field anchor: it must belong to the explicitly selected package, have a fixed reference pose and usable resolved size/pose, and pass the existing tracking, freshness and ambiguity gates. Auto size inference alone cannot choose the field. Use a short, reviewer-defined stable observation interval rather than accepting the first noisy frame.

Before accepting that candidate, compare its expected and observed **tag-center height** and **printed-plane tilt from vertical**. Expected values come from that tag's reference pose and the package's field-floor datum; do not assume every tag should be upright or at the same height. For a +Z-up field, expected center height is the reference center's Z minus the corresponding field-floor elevation. Expected tilt is `asin(abs(dot(normalField, upField)))`, matching the existing 0° vertical / 90° horizontal convention. It is distinct from camera incidence angle and printed-plane twist.

Observed height uses the existing gravity-vertical height above a separately confirmed matching field floor; observed tilt uses the matching source-frame tag pose and AR gravity. Confirm that the floor represents the field's declared mat/carpet datum, not a nearby table or ramp. Snapshot its identity, geometry and segment. Calculate and record these checks **before registration**: transforming the anchor into field coordinates and comparing it with the pose used to anchor it would force a circular pass.

| Candidate result | Required behavior |
| --- | --- |
| Height and tilt pass their configured tolerances, with usable pose data and passing full gravity/printed-up consistency | Accept as a **provisional, single-tag anchor**. Use its full pose and the reference layout to key all expected field placements; keep the anchor assumption visible. |
| Either available value exceeds tolerance, or gravity/printed-up consistency fails | Warn with expected/observed values, differences and any additional orientation reason; do not automatically anchor from that candidate. Offer recheck or another fixed tag. |
| Height/tilt/reference datum is unavailable | Show **unverified**, not incorrect or passed. Explain the missing input, such as “Select the field floor to check height.” Do not auto-accept as having passed both checks. |

Store positive, versioned height, tilt and full-gravity angular tolerances with walk settings and record the actual limits used. Select defaults through technical review and physical evidence rather than treating numerical equality as achievable sensor accuracy. Warning text must name the tag and chosen field/variant, for example: “Tag {id}: expected center height {expectedHeight} cm, observed {observedHeight} cm; expected tilt {expectedTilt}°, observed {observedTilt}°. Field not aligned from this tag.” Include signed height difference, absolute tilt difference, any gravity-angle discrepancy, allowed tolerances and a reason. Suggest checking the selected definition, print size, mounting and floor datum without claiming which one is wrong. Display unavailable quantities honestly and retain warnings/evidence in the walk.

Height and unsigned tilt alone do not verify horizontal location, field heading, the correct physical copy or upside-down mounting. Retain a full gravity/printed-up consistency check before acceptance: compare `R_F_D^T × up_F` with `R_W_D^T × up_W` in the same tag frame. Their angular difference can reject an upside-down print without needing field heading. Preserve the pre-alignment residuals; do not rotate the field's up axis or alter the floor/reference geometry to make a bad candidate fit. The rigid initialization equation above is a proposal subject to this gravity-consistency policy.

LiDAR itself is not mandatory when qualified pose-derived center height above a separately confirmed floor is available; retain the applied-size assumptions and height source. When required checks are unavailable, basic manually chosen registration can still be available as **unverified/provisional**, identifying exactly which checks are missing. It does not satisfy automatic height/tilt acceptance. Once aligned, use additional fixed tags/views and return-to-anchor observations to check agreement and drift. A later disagreeing tag produces a warning rather than silently rekeying the entire field. A passing first tag remains an assumed anchor until independently checked. [Field-layout accuracy and multi-tag agreement](https://docs.photonvision.org/en/v2026.3.2/docs/apriltag-pipelines/multitag.html).

The implemented registration states are unaligned, provisional and degraded, with explicit invalidation reasons. Height/tilt/gravity checks have separate pass/fail/unavailable status; passing them does not promote a single-tag anchor to independently verified placement. Tracking loss suspends placement; reset, interruption or segment change invalidates it. Reacquire/recheck before showing trusted geometry. Store updates with effective source times and generations so delayed detection jobs cannot use a newer segment/layout/registration accidentally.

A tag used as an anchor cannot certify its own placement. Any inspection residual must exclude that tag from initialization, registration and subsequent realignment, or use independently established control. Otherwise label it assumed/anchor-dependent. This follows [PLAN.md M3.5 and M5](PLAN.md).

For BIOBUZZ and other moving targets, show current camera/AR-relative observations with timestamps and freshness. An estimated field position requires independent field registration, such as surveyed controls or valid external localization. Do not retain a moving target's old location as a permanent expected tag plane or feed it into robot absolute localization.

## 5. AR view and walk inventory

Draw expected centers, IDs, oriented tag squares and optional normals using existing shared projection plus native drawing. Use the latest usable camera frame to project world placements; retain each observation's original frame for calculations. Apply preview zoom once. Clip behind-camera/offscreen geometry, bound label count and expose alignment state through accessible controls/readouts.

Keep separate visual states for expected/unseen geometry, currently detected tags, tags seen earlier, and unresolved/conflicting observations. Expected overlays can persist while the tag is out of view if registration remains usable; current detection outlines retain their freshness limit. A top-down map can use ForceField's calibration approach, with distinct symbols for nominal versus observed positions. Full meshes, occlusion, force heatmaps and virtual robot-camera views can follow later.

For the first version, one saved walk is one existing capture session with one pinned field package. Start/stop recording defines its observation interval; changing the selected field starts a new walk. Preview-only detections do not silently enter a later saved walk. Maintain the inventory natively from completed analysis observations, not the throttled React Native status stream. For FTC inputs, use fresh detections/acquisition timestamps so repeated reads of the last SDK result do not inflate counts.

Each unique physical tag row should contain:

- Program, season, variant, package hash, family/ID, name and optional cluster.
- First/last source timestamp, observation count, accepted/rejected counts and representative frame/bookmark links.
- **Published field position:** reference center XYZ/orientation, or an explicit unavailable/dynamic reason. Known IDs can show this even before alignment.
- **Observed position:** latest or reviewed estimate, frame/segment/registration identity, timestamp and quality/rejection status; null when unavailable.
- **Difference from reference:** translation/orientation residual only when a valid independent comparison exists.

Keep summary counts separate from sufficient observation diversity. An undetected tag is “not seen,” not proven absent. Unknown layout IDs retain available per-observation sizing/pose evidence with no invented nominal position. Reuse the existing detect-once/reference-pose/per-detection resolution path for mixed sizes; absent resolved size preserves ID/corners but prevents metric pose. An unknown layout ID and an unresolved physical size are distinct states.

FTC SDK 12 requires special handling: normal BIOBUZZ output is one cluster detection, with no public per-member ID/corner evidence. A partial cluster detection must not mark all its tags seen. [Cluster documentation](https://ftc-docs.firstinspires.org/en/latest/tech_tips/tech-tips/tech-tip-apriltag-clusters/tech-tip-apriltag-clusters.html), [Vision source artifact](https://repo.maven.apache.org/maven2/org/firstinspires/ftc/Vision/12.0.0/Vision-12.0.0-sources.jar).

The phone can retain member detections through its existing detector. For the deferred FTC robot integration, an inspection-specific library declaring members individually is a possible approach, separate from the normal cluster library for gameplay. SDK 12 rejects declaring a cluster and its member singleton IDs in the same library. A custom VisionProcessor is another later option if needed. Until member evidence is available, cluster-only input records “cluster seen; individual member visibility unknown.” Preserve cluster-relative geometry in every mode.

Fixed-tag estimates may aggregate qualified views within valid registrations. Moving-tag summaries show a latest timestamped estimate and trajectory/history; never average motion into a fixed field location. Preserve per-segment estimates and all raw observations when tracking resets.

## 6. Persistence and future robot interoperability

Snapshot the exact normalized YAML field package into each recording. Record field selection and registration creation/update/invalidation events, observation references and settings/core versions. Add a versioned `field-walk-summary.yaml`, with JSON and CSV export available for review; retain raw `events.jsonl` as evidence. Include new sidecars in the existing file inventory and MP4 TAR transport. Update playback timelines and seeking explicitly; transport inclusion alone does not draw field overlays. Older recordings without registration may acquire nominal positions from an explicitly selected layout, but must not acquire invented historical measured poses.

Current implementation covers iOS, host-side validation and replay. Keep the portable C ABI, YAML/JSON contract and source/frame identities suitable for later robot reuse. The robot rows and packaging notes below are retained as technical reference for deferred FD.5; they are not current tasks or acceptance dependencies.

| Consumer | Planned adapter |
| --- | --- |
| iOS | Swift loads YAML by default or JSON into the validated model and passes neutral structs to the C ABI. Save/display field definitions as YAML. Native capture/rendering remains in Swift; React Native receives bounded summaries and commands. |
| FRC 2026 / compatible PhotonVision | Our adapter loads YAML/default or JSON, and imports/exports legacy `AprilTagFieldLayout` JSON for fixed poses, plus our YAML manifest for family/size/provenance. Round-trip generated JSON through the actual Java/C++ readers. [Pinned legacy reader](https://github.com/wpilibsuite/allwpilib/blob/v2026.2.2/apriltag/src/main/java/edu/wpi/first/apriltag/AprilTagFieldLayout.java), [PhotonVision MultiTag](https://docs.photonvision.org/en/v2026.3.2/docs/apriltag-pipelines/multitag.html). |
| Existing FRC 2027 alpha-8 consumers | Add a YAML/default and JSON loader around the integrated Fields adapter. Generate compatible JSON or construct library objects before using native APIs: Java `Fields.<entry>.loadField()` / `Field.loadFromFile(Path)`; C++ `wpi::fields::GetField(...)` / `Field(path)`. Native serialization produces integrated JSON, so conversion to our YAML and export to legacy JSON must be explicit. [Java Field](https://github.com/wpilibsuite/allwpilib/blob/v2027.0.0-alpha-8/fields/src/main/java/org/wpilib/fields/Field.java), [C++ Field](https://github.com/wpilibsuite/allwpilib/blob/v2027.0.0-alpha-8/fields/src/main/native/include/wpi/fields/Field.hpp). |
| FTC Android robot | Build an SDK-version-specific `AprilTagLibrary`/cluster adapter from the same YAML/default or JSON input. The reviewed SDK has no native field-layout YAML/JSON reader; our loader must populate SDK Builders. Integrate camera input through VisionPortal; convert SDK raw/FTC poses deliberately, or use matching corners and intrinsics in the shared pose solver. Keep camera ownership with the SDK. |
| Desktop replay | Load the same package/core and original source observations; reproduce summaries and registration decisions without rewriting the recording. |

Extend the C ABI and Swift integration additively for neutral tag geometry, transforms, registration results and observation summaries. Preserve existing ABI/JNI compatibility without requiring new Java/Android bindings or parity work now. Preserve existing +Y-up floor APIs; add explicit field-frame operations instead of changing their meaning. Keep platform parsers/framework types outside the numerical core.

Extract the current Swift size resolver/rescaler into this boundary and drive its catalog from YAML. Depth is optional sensor input, with source confidence/availability semantics supplied by each adapter rather than inferred from an unrelated robot confidence score. The future robot design must retain explicit preset/package/custom sizing when suitable depth is absent; Auto reports unavailable when its inputs cannot be supplied. Do not substitute a reference size for an unresolved Auto result. Current size-policy fixtures compare Swift and host C++; Java/robot parity is deferred.

Deferred packaging note: the existing Android AAR is a starting point, not verified FTC integration. It has `minSdk=24`, `compileSdk=35`, Java 11 and `arm64-v8a`/`x86_64` builds, while FTC has its own toolchain and runtime ABI requirements. When FD.5 is separately scoped, pin the Robot Controller SDK/hardware, verify Android/API/ABI requirements, resolve native-library/STL conflicts and validate a real FTC sample. [Local Android build](bindings/android/build.gradle.kts), [FTC build configuration](https://github.com/FIRST-Tech-Challenge/FtcRobotController/blob/master/build.common.gradle).

Preserve source code/data contracts for future Apple, Systemcore and Android consumers. Later robot results will need camera calibration/extrinsics, sensor/clock identities, capture times and layout hashes; phone/robot clocks require explicit synchronization. These design constraints do not require robot builds, deployment, telemetry or odometry fusion during the current phone milestones. No network connection is required for the shared offline package.

Never export moving/unknown targets as fixed WPILib poses. Keep any later calibrated candidate map a separate reviewed artifact; a walk inventory must not overwrite the official reference or deploy changes to a robot.

## 7. Milestone checklist for a junior developer

The user explicitly authorized FD.1–FD.4 implementation on November 24, 2026, including proceeding before the remaining M0 field review and installing only after the FD.4 software checks. Completed items link to [FD.1 evidence](docs/validation/FD.1.md), [FD.2 evidence](docs/validation/FD.2.md), [FD.3 evidence](docs/validation/FD.3.md) and [FD.4 evidence](docs/validation/FD.4.md). This authorization does not complete the M0 physical-data review or FD.6 accuracy acceptance. Robot integration, future-season expansion, candidate-map export and richer visual layers remain deferred.

### How to use this checklist

The junior developer owns implementation, automated checks, reproducible demos and fixes. A technical reviewer checks schema decisions, coordinate math, registration policy and camera/clock conventions. The tester supplies physical captures and independent measurements; field construction and surveying are not assigned to the developer. Ordinary implementation continues within the reviewed contract without repeated approval requests.

Target roughly half a day to two developer days per implementation checkbox as a planning guide, not a delivery promise. Split larger work into additional stable subtask IDs before starting it. Keep the active FD.1–FD.4 and FD.6 task IDs stable; reserve FD.5 and FD.7 for deferred work without renumbering the current milestones. Use focused commits such as `feat(FD.3.4): retain native walk observations`.

For each checked item, record its commit/PR, exact validation command or procedure, result and remaining limitations in `docs/validation/FD.<milestone>.md`. These are proposed evidence files. Reference large captures by location/checksum rather than committing them. Check the item in the same commit as its deliverable. A milestone's `.G` exit stays unchecked until its required tasks and exit demonstration pass; compilation, fixture success and physical accuracy are separate results. Record unavailable data/hardware against the affected task and leave that task pending.

| Milestone | Prerequisites | Demonstrable result |
| --- | --- | --- |
| FD.1 | Existing M0 review gate | Reproducible YAML catalog with JSON compatibility and validated sources. |
| FD.2 | FD.1 schema/fixtures | Shared lookup, per-tag pose geometry and checked frame conversions. |
| FD.3 | FD.1 and FD.2.1–FD.2.2; may run alongside remaining FD.2 work | Saved walk lists actually seen tags and their nominal positions without registration or LiDAR. |
| FD.4 | FD.2 and FD.3 | Registered expected tag overlays with explicit lifetime and comparison status. |
| FD.6 | FD.3 and FD.4 phone software and their required FD.2 work | Independent physical phone evidence and reviewed limits on supported FTC/FRC fields. |

FD.5 (robot consumers/interchange) and FD.7 (FRC 2027 and optional visual layers) are deferred until much later and removed from the current checklist. Revisit their scope separately after the phone workflow and physical validation; source availability alone does not reactivate them. FTC 2026–2027 BIOBUZZ remains in current phone scope.

### FD.1 — Build the YAML field catalog

**Deliverable:** versioned packages under a proposed `fields/` directory and documented import/validation commands. Start with data and command-line validation before app UI.

- [x] **FD.1.1 — Create small examples.** Draft `manifest.yaml`, `tags.yaml` and `clusters.yaml` examples covering a fixed tag, an unknown field pose and a moving cluster. Include equivalent JSON examples with the same values.
- [x] **FD.1.2 — Write the schema contract.** Define required/optional fields, version handling, units, quaternion order, reference floor datum, derived center-height/tilt conventions, placement/anchor semantics and source/package hash rules. Keep configurable comparison tolerances separate from published tag geometry. The technical reviewer checks this contract before consumers depend on it.
- [x] **FD.1.3 — Select serialization dependencies.** Document YAML 1.2 support and licenses for the current Swift/host tools. Write one agreed valid/invalid sample set and preserve format portability; defer Java/Android parser packaging. Keep parsing outside AFSC math.
- [x] **FD.1.4 — Add a validator.** Report filename and field path for invalid input. Cover duplicate IDs/keys, missing size, unsupported family/version, bad units/transforms and broken cluster references; preserve explicit unavailable poses.
- [x] **FD.1.5 — Add conversion commands.** Accept YAML/default and JSON, validate through one model, and emit normalized YAML by default or JSON explicitly. Document commands and prove null/false/zero, precision and semantic identities survive round trips.
- [x] **FD.1.6 — Import FRC 2026 welded.** Convert the pinned source, record hashes/family/size, and compare all tag records plus dimensions to the source; independently spot-check representative poses.
- [x] **FD.1.7 — Import FRC 2026 AndyMark.** Create a distinct package and verify it retains its own geometry/dimensions. Make choosing a variant explicit; demonstrate that the two packages cannot be confused by year alone.
- [x] **FD.1.8 — Import FTC DECODE.** Preserve IDs 20–24 and explicit fixed-target versus Obelisk eligibility. Verify sizes, source units and unavailable global poses without promoting SDK placeholders to anchors.
- [x] **FD.1.9 — Import FTC BIOBUZZ.** Preserve all four named clusters, member IDs/sizes and local transforms. Verify moving-target eligibility, aiming origins and unavailable fixed field positions.
- [x] **FD.1.10 — Make imports reproducible.** Record pinned downloads/artifact hashes and extraction/conversion commands. Regenerate the packages and compare normalized output; document attribution before bundling assets. List FRC 2027 as unavailable rather than adding invented geometry.
- [x] **FD.1.11 — Reuse the existing size catalog.** Extract `TagFieldCatalog` presets/per-ID rules and `resolveTagSize` candidate widths/tolerances into the shared YAML catalog. Generate/load matching UI/native constants, preserve older size-only presets and verify that a size match never selects a field package or proves ID membership.
- [x] **FD.1.G — Exit demonstration.** From a clean checkout, run the documented imports and validator; load equivalent YAML/JSON and show the same catalog. Invalid fixtures fail with useful errors. Reviewer confirms source comparisons and anchor semantics; save the commands/results in the milestone evidence file.

### FD.2 — Implement portable tag lookup and geometry

**Deliverable:** small shared APIs and Swift integration, with independent numeric examples. Reuse `native/SpatialCore/`, `native/AprilTag/`, the Swift adapter and host C++ harness. This milestone does not require robot bindings or a field-registration optimizer.

- [x] **FD.2.1 — Define neutral inputs/results.** Add bounded tag/pose representations and explicit frame, package, source-observation and unavailable-reason fields. Describe memory ownership and additive C ABI/Swift changes while preserving compatibility for future bindings.
- [x] **FD.2.2 — Add indexed lookup.** Resolve tags by package/family/ID, including cluster members. Verify known, unknown and duplicate identities; return unavailable size/pose explicitly.
- [x] **FD.2.3 — Establish independent geometry examples.** Write expected numeric results for head-on, translated, rotated and inverse/composed transforms. Have the reviewer check frame directions, printed corner order and quaternion ordering before using these as expected results.
- [x] **FD.2.4 — Implement rigid transform helpers.** Compose/invert transforms and convert named quaternion/matrix representations. Reject invalid rotations/nonfinite inputs. Check against FD.2.3 rather than generating expected results with the helper under test.
- [x] **FD.2.5 — Implement ARKit/optical and WPILib conversions.** Exercise the camera-axis conversion and the distinct tag-basis conversion separately; verify expected centers, printed-up vectors and normals.
- [x] **FD.2.6 — Implement FTC conversions.** Preserve FTC's centered field frame; distinguish raw optical pose, `ftcPose`, cluster frame and tag frame. Verify inch-to-meter conversion and explicit member/aiming-origin transforms.
- [x] **FD.2.7 — Reuse per-detection resolution/rescaling.** Port the existing `resolveTagSize`/`rescaledPose` behavior into AFSC with optional matching-frame depth. Preserve unique-match tolerances, explicit-mode rules, metric error scaling and ID-only rejection behavior. Run mixed-size, same-ID/different-size and boundary fixtures against the existing Swift results and independently calculated scale cases.
- [x] **FD.2.8 — Connect Swift to the portable core.** Send the same fixtures through host C++ and the Swift adapter. Run relevant existing spatial-core checks and confirm the established +Y-up floor APIs retain their meaning. New JNI/Java consumers and cross-platform robot parity belong to deferred FD.5.
- [x] **FD.2.9 — Preserve settings and evidence compatibility.** Bridge Auto/FTC/FRC/Custom, legacy year semantics, Apply/Cancel and precise manual/AR overrides into the YAML-backed model. Preserve per-detection `tagSizeResolution` and applied scale; test missing/weak center depth, zero/multiple matches, invalid source tracking and unchanged historical observations.
- [x] **FD.2.G — Exit demonstration.** Load one FRC and one FTC YAML/JSON fixture through the current host/iOS paths and compare lookup, transform and per-tag pose results within a reviewer-documented numerical tolerance. Record rejected cases and C ABI compatibility results; no robot consumer build is required.

### FD.3 — Ship the saved-walk tag list

**Deliverable:** the first useful phone workflow: select a field, record a walk, reopen its tag list and export it. Reuse FD.1 packages and FD.2.1–FD.2.2 neutral types/lookup; measured-position fields may remain explicitly unavailable while the remaining FD.2 geometry and FD.4 registration work are in progress.

- [x] **FD.3.1 — Add catalog selection.** Expose program, full season and variant with package revision and unsupported/unavailable status. Check small/large layouts and accessible labels using the simulator.
- [x] **FD.3.2 — Add the YAML definition viewer/store.** Load YAML or JSON input, persist the validated field package as YAML and display formatted YAML. If database persistence is used, store the YAML document with identity/hash and demonstrate reload without losing semantic values.
- [x] **FD.3.3 — Pin the package to a walk.** Snapshot exact YAML bytes/hash at recording start, retain their identity on observations and require a new walk to change the field. Check preview/start/stop/background boundaries.
- [x] **FD.3.4 — Maintain the native inventory.** Implement a deterministic reducer in the portable core with a native Swift adapter. Consume completed source observations once, keyed by package/family/ID; retain first/last times, counts, quality/rejection counts and evidence references. Keep geometry inputs optional so registration math is not a prerequisite. Repeated UI status reads must not add observations.
- [x] **FD.3.5 — Handle unknowns and clusters.** Preserve decoded IDs when metric pose is rejected. Show null nominal positions with reasons for unknown/moving tags; cluster-only input must not mark individual members seen.
- [x] **FD.3.6 — Add the visible tag list.** Show each seen tag's identity, nominal XYZ/frame and observed-position status. Link to its representative frame/bookmark; distinguish not-seen reference tags from seen rows.
- [x] **FD.3.7 — Save and reopen summaries.** Write versioned `field-walk-summary.yaml`; reopen saved sessions and offer JSON/CSV export. Preserve per-segment evidence and keep moving-target positions timestamped.
- [x] **FD.3.8 — Extend transport and replay.** Include YAML packages/summaries in the inventory/MP4 export, restore them byte-for-byte through extraction, and reproduce the summary from original events. Older recordings retain explicit missing package/registration state.
- [x] **FD.3.9 — Verify walk edge cases.** Exercise empty/failed analysis, repeated/late results, unknown IDs, rejected metric poses, recording restarts, segment resets and partial clusters. Demonstrate that UI throttling and missing LiDAR do not change the seen list.
- [x] **FD.3.10 — Separate size and layout identity.** Persist/display per-observation size resolution alongside the pinned field package. Test Auto preview with no package, Auto/Custom with an explicitly chosen walk package, practice IDs with valid sizes but unknown field positions, and observed/reference size conflicts. Auto/Custom year `0` must not clear the walk's package selection.
- [x] **FD.3.G — Exit demonstration.** Select each supported package, replay a saved walk, then save/export/reopen it. Compare IDs, nominal positions, counts, hashes and evidence references. The list works with no field registration and no depth stream; measured positions are honestly unavailable.

### FD.4 — Place expected tags in AR

**Deliverable:** a bounded registration and overlay workflow built on the reviewed equations in section 4. The junior implements the agreed baseline; a full calibration/bundle-adjustment solver remains separate M5 work.

- [x] **FD.4.1 — Define registration state.** Represent transform, field/segment identity, source times, generation, assumed anchors and unaligned/provisional/degraded status and explicit invalidation reasons. Include per-candidate height/tilt pass/fail/unavailable status and the floor/threshold snapshots. Write the state-transition table and have the reviewer check acceptance/rejection policy.
- [x] **FD.4.2 — Initialize from the first qualified fixed tag.** After FD.4.12, propose the first known eligible tag and auto-initialize only when its independent height/tilt and gravity-consistency checks pass. Use the matching source-frame full pose to key the field and label the result provisional/anchor-dependent. Reject moving, stale, ambiguous or conflicting candidates. Keep any manual unverified fallback clearly separate from automatic acceptance.
- [x] **FD.4.3 — Enforce lifetime and concurrency.** Invalidate or suspend registration on reset, interruption, tracking loss and package changes. Check delayed jobs against their source segment/package/generation before accepting them.
- [x] **FD.4.4 — Project expected centers and IDs.** Transform reference geometry into the AR world and reuse `SpatialProjection`. Verify near-plane/offscreen clipping and current-camera projection separately from source-observation math.
- [x] **FD.4.5 — Draw squares and normals.** Add oriented tag edges and optional axes/normals. Verify phone rotation, preview modes, 1×/2×/4× zoom and tags outside the view; apply display magnification once.
- [x] **FD.4.6 — Expose status and controls.** Provide accessible align/recheck/clear controls and distinct expected/currently-seen/previously-seen/unresolved states. For a failed anchor candidate, show tag/field identity, expected and observed height/tilt, differences, tolerances and suggested checks; missing data shows unverified with a specific next step. Retain the warning in the walk. Expected geometry may persist out of view only while registration remains usable.
- [x] **FD.4.7 — Check agreement and drift.** Under reviewer-specified thresholds/method, compare additional fixed-tag observations and return-to-anchor observations with the provisional registration. Warn about disagreement without silently rekeying the field, snapping geometry or averaging conflicting poses. Keep a single-tag anchor assumption distinct from independently checked placement.
- [x] **FD.4.8 — Add independent comparison status.** Track which tags contributed to initialization and realignment. Exclude the tag under inspection from its registration chain, or label the comparison assumed/unresolved. Demonstrate that a planted moved tag cannot certify itself.
- [x] **FD.4.9 — Handle moving-target observations.** Display fresh tag/cluster estimates with timestamps in the camera/AR frame, or the field frame only with independent registration. Expire old placements and never feed them into fixed-anchor registration.
- [x] **FD.4.10 — Save and replay overlay state.** Record registration changes with effective source times and reconstruct them during playback, pause and seek. Verify resets, stale jobs and unavailable historical registration using the simulator/replay harness.
- [x] **FD.4.11 — Carry sizing assumptions into registration.** Use each source observation's applied scale and provenance; invalidate affected state when sizing policy changes. Show size/reference conflicts as assumed/unresolved and verify that Auto-derived LiDAR agreement does not count as an independent size or placement check.
- [x] **FD.4.12 — Evaluate anchor height/tilt before registration.** After FD.4.1 and before FD.4.2, derive expected values from the reference pose/floor datum and reuse matching-frame `TagFloorHeight`/`TagGravityOrientation` observations. Return per-check values, residuals, tolerances, source identities and pass/fail/unavailable reasons. Compare full gravity in the tag frame to catch printed-up disagreement; a proposed registration must never supply its own validation datum.
- [x] **FD.4.13 — Verify first-anchor scenarios.** Cover correct height/tilt, wrong height, wrong tilt, intentionally sloped reference tags, upside-down tags, missing/wrong floor datum, unknown/moving tags and noisy/stale observations. Verify clear expected-versus-observed warnings, no automatic alignment on failed/incomplete checks, and no field jump when a later tag disagrees. Include a horizontally displaced tag with correct height/tilt to demonstrate the remaining provisional assumption.
- [x] **FD.4.G — Exit demonstration.** Run independent geometry and recorded-walk cases through alignment, expected rendering, tracking loss/recovery and playback. Reviewer checks the comparison/anchor behavior; the evidence labels simulator/replay results separately from physical accuracy.

### FD.6 — Validate physical walks and report limits

**Deliverable:** physical phone evidence and a reproducible report for each claimed capability on supported FTC/FRC fields. The junior prepares the iOS build and analysis; the tester owns field access, independent control/measurements and captures. Robot hardware, robot software and FRC 2027 data are not prerequisites. Record unavailable field cases against the affected phone acceptance task.

- [ ] **FD.6.1 — Prepare the acceptance matrix.** List FRC fixed tags, FTC fixed tags and FTC moving/partial-cluster cases separately. Include first-anchor height/tilt acceptance and explained warnings. With the reviewer/tester, define independent controls, intended accuracy/coverage and anchor tolerances, and pass/unresolved conditions before inspecting acceptance results.
- [ ] **FD.6.2 — Prepare builds and the run sheet.** Complete simulator/replay checks, package builds and concise tester instructions before starting any physical session. Include version/package hashes and how to export the complete recording.
- [ ] **FD.6.3 — Verify physical-session cleanup.** For every physical iOS action, follow the [iOS testing skill](/Users/horner/.codex/skills/ios-testing/SKILL.md) and [device-session guard](/Users/horner/.codex/skills/ios-testing/references/device-session-guard.md). Record the owned global lease/session and complete verified release before coding, analysis, waiting or handoff; an unverified release remains open work.
- [ ] **FD.6.4 — Tester: capture fixed-tag cases.** Walk FRC 2026 and FTC DECODE cases using independent references, varied views, a return to starting controls and an interruption/reset. Check first-anchor acceptance and warnings against independently known height/tilt discrepancies where available, including a missing/incorrect floor reference. Record unperformed cases separately.
- [ ] **FD.6.5 — Tester: capture moving/cluster cases.** Use the phone to observe BIOBUZZ target movement and partial visibility. Check actually detected member IDs, timestamps, preservation of unseen-member status and unavailable global position without independent registration. Keep this task pending if field access is unavailable; FTC robot integration is not required.
- [ ] **FD.6.6 — Reproduce and compare.** Verify exported hashes/extraction, replay the original phone observations and compare coverage, independent position/orientation differences and drift to the predetermined criteria. Produce separate results for the tested FRC/FTC field cases with missing/rejected data visible.
- [ ] **FD.6.7 — Review and fix findings.** Attach the report and exact reproduction steps to focused repair tasks. The reviewer checks claims against evidence; rerun affected checks after repairs. Reserve fresh acceptance data if earlier results were used to tune the implementation.
- [ ] **FD.6.8 — Validate Auto sizes independently.** Extend the existing pending Auto-size checks with independently measured prints, mixed sizes, 6/6.5-inch cases, varying views/ranges and weak/missing depth. Compare inferred/applied widths to the physical measurements separately from LiDAR agreement; retain manual/custom fallback and the native accessibility follow-up until verified.
- [ ] **FD.6.G — Exit demonstration.** Required physical cases and repairs pass with reviewed limitations, readable exports and verified device release. Record user review. Partial software/physical slices may be reported as complete individually; pending required cases prevent an overall accuracy claim.

The earliest usable handoff is FD.1, FD.2.1–FD.2.2 and FD.3: a saved, exportable list of actually seen tags and their nominal positions. The remaining FD.2 work and FD.4 add registered AR geometry and defensible comparison states, followed by FD.6 physical phone validation. Robot delivery and future-season/visualization expansion can be scoped much later. FTC moving targets remain time-dependent observations throughout the current phone checklist.
