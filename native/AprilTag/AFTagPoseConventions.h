#ifndef AF_TAG_POSE_CONVENTIONS_H
#define AF_TAG_POSE_CONVENTIONS_H

#ifdef __cplusplus
extern "C" {
#endif

/* These are additive camera-relative readouts. AFTagPose and the shared spatial
 * core retain their original optical-coordinate contracts and ABI layouts.
 * Lengths are meters; angles are degrees. All matrices are row-major and map
 * tag-local column vectors into camera coordinates, without robot extrinsics
 * or a field-layout transform.
 */
typedef struct {
    double translationMeters[3]; /* FTC camera: +X right, +Y forward, +Z up. */
    double rotationRowMajor[9];  /* C R_opt C^-1, with C:(x,y,z)->(x,z,-y). */
    double pitchDegrees, rollDegrees, yawDegrees;
    double planarRangeMeters;  /* SDK range: hypot(x,y), not 3-D distance. */
    double bearingDegrees;     /* SDK bearing: atan2(-x,y), positive left. */
    double elevationDegrees;   /* SDK elevation: atan2(z,y), not atan2(z,range). */
    int eulerSingular;
} AFTagFTCPose;

typedef struct {
    double translationMeters[3]; /* PhotonVision/WPILib camera NWU: forward,left,up. */
    double rotationRowMajor[9];  /* B R_opt Ry(pi) B^-1, not just B R_opt B^-1. */
    double rollDegrees, pitchDegrees, yawDegrees;
    double euclideanRangeMeters; /* Camera-to-tag-center 3-D distance. */
    int eulerSingular;
} AFTagFRCPose;

/* FTC SDK camera-pose convention, checked against published Vision/RobotCore
 * 11.1.0 and 12.0.0 sources. The SDK extracts intrinsic YXZ from the raw optical
 * rotation, sets yaw=-first, pitch=second, roll=third, normalizes each extracted
 * angle to [-180,180), and selects the lower-magnitude of its two Euler sets.
 * Matrix/angle intermediates intentionally match the SDK's float precision.
 * The negation is applied after SDK normalization, so yaw can equal +180.
 * At singularity the SDK chooses roll=0; the matrix remains authoritative.
 * Sources: org.firstinspires.ftc Vision and RobotCore source JARs at
 * https://repo.maven.apache.org/maven2/org/firstinspires/ftc/
 */
int AFTagConvertOpticalPoseToFTC(const double opticalTranslationMeters[3],
                               const double opticalRotationRowMajor[9],
                               AFTagFTCPose *output);

/* PhotonVision v2026.3.3 camera-to-target convention: first apply its AprilTag
 * tag-basis correction Ry(pi), then convert the complete transform EDN->NWU.
 * B:(x,y,z)->(z,-x,-y). A front-on upright raw identity rotation consequently
 * becomes an NWU rotation of 180 degrees about +Z. Euler extraction follows
 * WPILib Rotation3d's extrinsic XYZ (roll,pitch,yaw), including its singularity
 * choice roll=0. This is a PhotonVision interoperability convention, not a claim
 * that every FRC vision provider has an identical output contract.
 * Sources: PhotonVision v2026.3.3 MathUtils.java; WPILib v2026.2.2
 * CoordinateSystem.java and Rotation3d.java. Formulas are implemented directly
 * from the basis transforms and rotation identities; no runtime SDK dependency.
 */
int AFTagConvertOpticalPoseToFRC(const double opticalTranslationMeters[3],
                               const double opticalRotationRowMajor[9],
                               AFTagFRCPose *output);

/* Both functions return 1 on success, 0 for null/nonfinite inputs, a nonproper
 * rotation, nonpositive optical depth, or nonfinite results. Non-null output is
 * zeroed on failure. They do not mutate inputs or use cached Euler/range values.
 */

#ifdef __cplusplus
}
#endif
#endif
