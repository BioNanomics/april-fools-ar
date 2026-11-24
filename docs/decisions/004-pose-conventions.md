# Explicit camera-relative tag pose conventions

Status: accepted, 2026-11-24. Convention version: 1.

The app supports FTC and FRC users while preserving its standard raw AprilTag optical pose. A camera-relative tag observation, a phone attitude, a robot pose and a field pose are different quantities. Every readout and serialized derived pose must name its reference and bases. Physical tag-size selection is independent of pose presentation.

## Profiles

The saved `poseConvention` setting selects `rawOptical`, `ftcSdk`, or `frcPhotonVision`; the default is `frcPhotonVision`. Auto sizing, explicit FTC/FRC size presets, field package selection and decoded IDs do not change this setting.

| Profile | Camera +X / +Y / +Z | Tag-local +X / +Y / +Z | Head-on upright tag |
| --- | --- | --- | --- |
| Raw optical | right / down / forward | printed right / printed down / into print | identity rotation; Rot X/Y/Z = 0° |
| FTC SDK | right / forward / up | printed right / into print / printed up | pitch/roll/yaw = 0° |
| FRC / PhotonVision | forward / left / up | out of print / printed right / printed up | roll/pitch = 0°, pose yaw = 180° |

Camera directions refer to the original captured sensor orientation, before display rotation, crop or zoom. A profile's camera-up direction need not be gravity-up. The projected RGB tag-axis gizmo retains the raw tag basis, independently of the selected readout profile.

## Matrix meaning and raw optical contract

Use column vectors and name the destination/source frames explicitly:

```text
pCamera = R_cameraFromTag × pTag + t_cameraFromTag
```

The translation is the tag origin expressed in camera coordinates. This matrix maps tag-coordinate points to camera-coordinate points; it is not the inverse point-coordinate transform. Calling a robotics pose object a “camera-to-target transform” describes a relative frame pose, and must not obscure this point mapping. To express a camera-coordinate point in the tag frame, use `Rᵀ × (pCamera − t)`.

Raw optical axes follow [AprilTag](https://github.com/AprilRobotics/apriltag#coordinate-system) and [OpenCV](https://docs.opencv.org/4.x/d5/d1f/calib3d_solvePnP.html). The low-level `AFTagPose` and capture `pose` contracts remain unchanged: translation in meters, `rotationRowMajor`, and legacy `eulerDegrees` in optical axes. The raw Euler order is `Rz(Rot Z) Ry(Rot Y) Rx(Rot X)`. At raw pitch/Rot Y singularity, Rot X is zero by convention; the matrix is authoritative.

ARKit camera coordinates differ from optical coordinates. World composition remains:

```text
T_worldFromTag = T_worldFromARCamera × diag(1,−1,−1,1) × T_opticalFromTag
```

ARKit world +Y is gravity-up, and the world origin/heading are session-relative until an explicit field alignment is established. Neither a display profile nor a selected tag-size preset supplies camera mounting extrinsics or field localization.

## FTC SDK adapter

The implementation matches the published FTC Vision and RobotCore 11.1.0/12.0.0 source contracts. The [official conversion example](https://ftc-docs.firstinspires.org/en/latest/apriltag/vision_portal/apriltag_intro/apriltag-intro.html#advanced-use) is also useful; formulas in the published implementation resolve prose descriptions that simplify range to a direct distance.

```text
C = [ 1  0  0 ]
    [ 0  0  1 ]
    [ 0 −1  0 ]

tFTC = C × tOptical = (opticalX, opticalZ, −opticalY)
RFTC = C × ROptical × Cᵀ
```

The SDK extracts intrinsic YXZ angles `(a,b,c)` from the raw matrix and returns `yaw = −a`, `pitch = b`, `roll = c`. The resulting FTC matrix factors as `Rz(yaw) Rx(pitch) Ry(roll)`. Thus pitch is about FTC X right, roll about Y forward and yaw about Z up. All use the right-hand rule. In ordinary orientations, positive roll turns the print clockwise through the camera; positive tag pitch tips its face downward; positive yaw is counterclockwise from above.

Exact interoperability includes float intermediate values, normalized angle branches, the SDK's smaller-magnitude choice between two equivalent Euler sets, and roll = 0 at its singularity. Simply swapping or renaming the old optical Euler values is incorrect for mixed-axis rotations. [Vision 12.0.0 source](https://repo.maven.apache.org/maven2/org/firstinspires/ftc/Vision/12.0.0/Vision-12.0.0-sources.jar), [RobotCore 12.0.0 source](https://repo.maven.apache.org/maven2/org/firstinspires/ftc/RobotCore/12.0.0/RobotCore-12.0.0-sources.jar).

FTC's derived center quantities are:

```text
planarRange = hypot(ftcX, ftcY)
bearing     = atan2(−ftcX, ftcY)    // +left, −right
elevation   = atan2(ftcZ, ftcY)     // +up, −down
```

Range is a camera-XY-plane projection, excluding camera-relative vertical displacement. Calling it ground range requires a level camera. SDK elevation uses forward Y as its denominator, not planar range; it is a projected vertical aiming angle, separate from spherical elevation. Bearing/elevation describe the center ray, rather than the tag's pose yaw/pitch.

## FRC / PhotonVision adapter

This profile matches PhotonVision **2026.3.3** and WPILib **2026.2.2**, rather than asserting a universal contract for every FRC vision provider. [WPILib's common NWU frame](https://docs.wpilib.org/en/stable/docs/software/basic-programming/coordinate-system.html) has X forward, Y left, Z up. The low-level WPILib AprilTag estimator still returns the upstream raw optical pose; a `Transform3d` type alone does not perform this conversion.

PhotonVision first corrects the raw tag's into-print basis by a local `Ry(π)` and then changes the complete transform from EDN to NWU:

```text
B = [ 0  0  1 ]       A = Ry(π) = diag(−1,1,−1)
    [−1  0  0 ]
    [ 0 −1  0 ]

tFRC = B × tOptical = (opticalZ, −opticalX, −opticalY)
RFRC = B × ROptical × A × Bᵀ
```

The local correction is essential: a basis conjugation alone would incorrectly leave a head-on tag at identity. This adapter places its tag X out of the printed front, Y printed right and Z printed up; a head-on upright tag has rotation 180° about camera Z. [PhotonVision camera/tag frames](https://docs.photonvision.org/en/latest/docs/apriltag-pipelines/coordinate-systems.html), [pinned correction implementation](https://github.com/PhotonVision/photonvision/blob/v2026.3.3/photon-core/src/main/java/org/photonvision/common/util/math/MathUtils.java), [pinned WPILib transform basis conversion](https://github.com/wpilibsuite/allwpilib/blob/v2026.2.2/wpimath/src/main/java/edu/wpi/first/math/geometry/CoordinateSystem.java).

WPILib rotation uses extrinsic XYZ / equivalent intrinsic ZYX: `R = Rz(yaw) Ry(pitch) Rx(roll)`, with right-hand angles about camera X/Y/Z. The adapter follows the [pinned Rotation3d extraction](https://github.com/wpilibsuite/allwpilib/blob/v2026.2.2/wpimath/src/main/java/edu/wpi/first/math/geometry/Rotation3d.java), including its singularity behavior. PhotonVision's separate `getYaw()` and `getPitch()` are target-center aiming measurements, not these pose Euler components.

## Distances, depth and viewing geometry

The pose's 3D camera distance is `hypot(hypot(x,y),z)` and is invariant under either profile change. Forward optical pose depth is raw `t.z`, corresponding to FTC Y and FRC X. ARKit scene depth is a camera-plane depth, not a spherical distance or raw LiDAR return. Its unprojection is `((u−cx)z/fx, (v−cy)z/fy, z)` in optical coordinates. [Apple ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata), [Apple's unprojection example](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth).

Visible diagnostic names are **Pose Z**, **Scene Z**, **|Δ Z|**, **3D dist**, **Incidence**, and **Axis offset**:

- Pose Z and Scene Z always use raw optical Z, even in a profile whose Z means up. Their absolute difference is the existing depth check.
- Viewing incidence is `acos(abs(normal · normalizedCenterRay))`: 0° head-on, 90° edge-on. It drives the existing viewing-angle check.
- Optical-axis offset is `atan2(hypot(rawX,rawY),rawZ)`, an unsigned full 3D center-ray angle. The old UI name **Bearing** is retired for this quantity; the old capture key `centerBearingDegrees` retains this meaning as a legacy alias.
- The actual tag pose algorithm is homography initialization plus two-candidate orthogonal iteration. **PnP** is a general problem name; it is not a claim that the app calls OpenCV `solvePnP`. The old **PnP Z** label becomes Pose Z. [Upstream pose API](https://github.com/AprilRobotics/apriltag/blob/master/apriltag_pose.h).

For optical translation `(3,−4,4)` m:

| Quantity | Expected value |
| --- | --- |
| FTC translation | `(3,4,4)` m |
| FRC translation | `(4,−3,4)` m |
| 3D camera distance, all profiles | `sqrt(41)` ≈ 6.403 m |
| FTC planar range | 5 m |
| FTC horizontal bearing | ≈ −36.87° |
| FTC elevation | +45° |
| Optical-axis offset | ≈ 51.34° |

Auto size resolution uses same-frame scene depth to choose a nominal width, so subsequent pose/scene agreement is partly correlated by design. It cannot independently establish physical print size, accuracy or competition identity.

## App-derived gravity measurements

**Lean** replaces Tilt: unsigned printed-plane departure from vertical, `asin(abs(normalWorld · worldUp))`, 0° vertical / 90° horizontal. **Upright** replaces Twist: clockwise-positive printed rotation from gravity-defined upright projected into the tag plane, viewed from the printed front. It is unavailable for a horizontal plane. These are useful app-defined measurements, distinct from SDK pose roll/pitch/yaw and floor tilt. New explicit keys `planeLeanFromVerticalDegrees` / `uprightRotationClockwiseDegrees` accompany numerically identical legacy aliases `tiltFromVerticalDegrees` / `twistDegrees`; calculations and gravity alignment remain unchanged. A readout profile cannot change them.

## Additive recording contract and compatibility

`poseReadout` records convention version 1 and reference `tag-relative-to-camera`. It carries the convention key, exact `cameraFrame` and `tagFrame`, required `rotationConvention` interpretation, units (`length: meter`, `angle: degree`), `matrixOrder: row-major`, `translationMeters`, `rotationRowMajor`, `rollPitchYawDegrees`, `cameraDistanceMeters` and `eulerSingular`. FTC alone additionally supplies `planarRangeMeters`, `horizontalBearingDegrees` and `elevationDegrees`.

The stored Euler array is **always `[roll,pitch,yaw]`**. FTC's UI displays Pitch / Roll / Yaw by indexing that array explicitly. Raw optical labels the same X/Y/Z decomposition Rot X / Rot Y / Rot Z. Readers must validate the named convention/version and matrix semantics rather than guessing from displayed order or a tag-size preset.

The legacy raw `pose.translation`, `rotationRowMajor`, `eulerDegrees`, `rangeMeters`, `opticalAxisAngleDegrees`, `planeAngleDegrees` and existing debug/depth fields retain their numeric meaning. New serialized names add explicit interpretation; they do not reinterpret old recordings. Playback preserves recorded derived metadata when available and handles old optical-only observations through the documented raw contract. Historical files are not rewritten to acquire a purported SDK profile or competition identity.

## Validation requirements

Portable adapter tests use independent full rotation matrices, including mixed-axis rotations, head-on 0° versus 180°, angle wrapping and singularities. They check orthonormality, determinant +1, norm preservation, invalid-input rejection and FTC projected range/bearing/elevation. SDK-generated fixtures check the exact FTC branch behavior. UIKit checks every profile's order, axis labels, help anchors, missing data, accessibility and layout. Recording/playback checks retain raw geometry and validate canonical/legacy gravity aliases; the pose-readout decoder separately rejects mismatched convention metadata. Sensor accuracy still requires independently measured physical evidence; these numerical tests establish conventions and transport behavior.
