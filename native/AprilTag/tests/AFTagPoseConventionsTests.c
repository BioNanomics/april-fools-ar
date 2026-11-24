#include "../AFTagPoseConventions.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Standalone: cc -std=c11 -Wall -Wextra -Werror
 * native/AprilTag/AFTagPoseConventions.c
 * native/AprilTag/tests/AFTagPoseConventionsTests.c -lm -o /tmp/pose-conventions
 */
static const double pi = 3.14159265358979323846264338327950288;
#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); \
} } while (0)

static void near(double actual, double expected, double tolerance) {
    if (!isfinite(actual) || fabs(actual - expected) > tolerance) {
        fprintf(stderr, "FAIL: got %.15g, expected %.15g within %.3g\n", actual, expected, tolerance);
        exit(1);
    }
}
static void matrixNear(const double *actual, const double *expected, double tolerance) {
    for (int i = 0; i < 9; ++i) near(actual[i], expected[i], tolerance);
}
static void multiply(const double *left, const double *right, double *output) {
    double result[9] = {0};
    for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c)
        for (int k = 0; k < 3; ++k) result[3*r+c] += left[3*r+k] * right[3*k+c];
    memcpy(output, result, sizeof(result));
}
static void axisRotation(int axis, double degrees, double *output) {
    memset(output, 0, 9 * sizeof(double));
    output[0] = output[4] = output[8] = 1;
    double c = cos(degrees * pi / 180), s = sin(degrees * pi / 180);
    int a = (axis + 1) % 3, b = (axis + 2) % 3;
    output[3*a+a] = c; output[3*a+b] = -s;
    output[3*b+a] = s; output[3*b+b] = c;
}
static void rawFromFTC(double yaw, double pitch, double roll, double *output) {
    double y[9], x[9], z[9], first[9];
    axisRotation(1, -yaw, y); axisRotation(0, pitch, x); axisRotation(2, roll, z);
    multiply(y, x, first); multiply(first, z, output);
}
static void rawFromOpticalXYZ(double roll, double pitch, double yaw, double *output) {
    double x[9], y[9], z[9], first[9];
    axisRotation(0, roll, x); axisRotation(1, pitch, y); axisRotation(2, yaw, z);
    multiply(z, y, first); multiply(first, x, output);
}

static void testTranslationsRangesAndIndependentSignedAngles(void) {
    const double identity[9] = {1,0,0,0,1,0,0,0,1}, translation[3] = {3,-12,4};
    AFTagFTCPose ftc; AFTagFRCPose frc;
    CHECK(AFTagConvertOpticalPoseToFTC(translation, identity, &ftc));
    CHECK(AFTagConvertOpticalPoseToFRC(translation, identity, &frc));
    near(ftc.translationMeters[0], 3, 0); near(ftc.translationMeters[1], 4, 0); near(ftc.translationMeters[2], 12, 0);
    near(ftc.planarRangeMeters, 5, 1e-12); near(frc.euclideanRangeMeters, 13, 1e-12);
    near(ftc.bearingDegrees, -36.86989764584402, 1e-12);
    near(ftc.elevationDegrees, 71.56505117707799, 1e-12);
    /* Elevation uses forward Y, not planar range: atan2(12,5) would be different. */
    CHECK(fabs(ftc.elevationDegrees - atan2(12, 5) * 180 / pi) > 1);
    near(frc.translationMeters[0], 4, 0); near(frc.translationMeters[1], -3, 0); near(frc.translationMeters[2], 12, 0);
    const double negative[3] = {-3,12,4};
    CHECK(AFTagConvertOpticalPoseToFTC(negative, identity, &ftc));
    near(ftc.bearingDegrees, 36.86989764584402, 1e-12);
    near(ftc.elevationDegrees, -71.56505117707799, 1e-12);
    const double centered[3] = {0,0,2};
    CHECK(AFTagConvertOpticalPoseToFTC(centered, identity, &ftc));
    near(ftc.bearingDegrees, 0, 0); near(ftc.elevationDegrees, 0, 0);
}

static void testActualFTCSDKGoldenAngles(void) {
    /* Golden [yaw,pitch,roll] values were obtained from the unmodified official
     * RobotCore Orientation/AngleUnit sources, published SDKs 11.1.0 and 12.0.0.
     * Their results are identical. MatrixF inputs and all Euler intermediates
     * are floats. These examples exercise the SDK's alternate-branch heuristic,
     * normalization and singularity choices, rather than just a matrix roundtrip.
     */
    const struct { double input[3], expected[3]; int singular; } cases[] = {
        {{25,-30,40}, {24.999998092651367,-30,40}, 0},
        {{20,110,-30}, {19.999998092651367,110,-30}, 0},
        {{170,100,160}, {-9.999999046325684,79.99999237060547,-19.999998092651367}, 0},
        {{20,90,30}, {49.999996185302734,90,0}, 1},
        {{20,-90,30}, {-10,-90,0}, 1},
        {{20,89.999,30}, {49.999996185302734,90,0}, 1},
        {{20,90.001,30}, {49.999996185302734,90,0}, 1},
        {{20,-89.999,30}, {-10,-90,0}, 1},
        {{20,89.98,30}, {19.999998092651367,89.98020935058594,30}, 0},
        {{180,0,0}, {180,0,0}, 0},
        {{-180,0,0}, {180,0,0}, 0},
        {{0,0,180}, {0,0,-180}, 0}
    };
    const double translation[3] = {0.3,-0.4,2};
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        double rotation[9]; AFTagFTCPose result;
        rawFromFTC(cases[i].input[0], cases[i].input[1], cases[i].input[2], rotation);
        CHECK(AFTagConvertOpticalPoseToFTC(translation, rotation, &result));
        near(result.yawDegrees, cases[i].expected[0], 1e-8);
        near(result.pitchDegrees, cases[i].expected[1], 1e-8);
        near(result.rollDegrees, cases[i].expected[2], 1e-8);
        CHECK(result.eulerSingular == cases[i].singular);
    }
}

static void testFTCRotationReexpressesBothBases(void) {
    const double translation[3] = {0.3,-0.4,2};
    const double c[9] = {1,0,0,0,0,1,0,-1,0}, inverse[9] = {1,0,0,0,0,-1,0,1,0};
    for (int yaw = -160; yaw <= 160; yaw += 40) for (int pitch = -80; pitch <= 80; pitch += 40)
        for (int roll = -160; roll <= 160; roll += 40) {
            double rotation[9], first[9], expected[9]; AFTagFTCPose result;
            rawFromFTC(yaw, pitch, roll, rotation);
            CHECK(AFTagConvertOpticalPoseToFTC(translation, rotation, &result));
            multiply(c, rotation, first); multiply(first, inverse, expected);
            matrixNear(result.rotationRowMajor, expected, 1e-12);
            /* FTC angles reconstruct in its axes as Rz(yaw) Rx(pitch) Ry(roll). */
            double z[9], x[9], y[9], reconstructed[9];
            axisRotation(2, result.yawDegrees, z); axisRotation(0, result.pitchDegrees, x); axisRotation(1, result.rollDegrees, y);
            multiply(z, x, first); multiply(first, y, reconstructed);
            matrixNear(reconstructed, result.rotationRowMajor, 2e-6);
        }
}

static void testPhotonVisionTagBasisAndIndependentGoldenAngles(void) {
    const double translation[3] = {0.3,-0.4,2};
    const double identity[9] = {1,0,0,0,1,0,0,0,1};
    const double frontOn[9] = {-1,0,0,0,-1,0,0,0,1};
    AFTagFRCPose result;
    CHECK(AFTagConvertOpticalPoseToFRC(translation, identity, &result));
    matrixNear(result.rotationRowMajor, frontOn, 0);
    near(result.rollDegrees, 0, 1e-12); near(result.pitchDegrees, 0, 1e-12); near(result.yawDegrees, 180, 1e-12);
    const struct { double raw[3], frc[3]; } cases[] = {
        {{30,0,0}, {0,30,180}}, {{0,30,0}, {0,0,150}}, {{0,0,30}, {-30,0,180}},
        {{12,-28,33}, {-32.08044893658773,25.11740293483954,-162.5252022088979}}
    };
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        double rotation[9]; rawFromOpticalXYZ(cases[i].raw[0],cases[i].raw[1],cases[i].raw[2],rotation);
        CHECK(AFTagConvertOpticalPoseToFRC(translation, rotation, &result));
        near(result.rollDegrees,cases[i].frc[0],1e-10);
        near(result.pitchDegrees,cases[i].frc[1],1e-10);
        near(result.yawDegrees,cases[i].frc[2],1e-10);
    }
    const double compoundMatrix[9] = {
        -.863653069528649,.469471562785891,-.183575126934770,
        -.271891171061728,-.740502159169041,-.614598847513295,
        -.424474459293402,-.480887724943527,.767182135744970};
    matrixNear(result.rotationRowMajor,compoundMatrix,1e-14);
}

static void testFRCRotationAndSingularity(void) {
    const double translation[3] = {0.2,0.1,2};
    const double b[9] = {0,0,1,-1,0,0,0,-1,0}, inverse[9] = {0,-1,0,0,0,-1,1,0,0};
    const double correction[9] = {-1,0,0,0,1,0,0,0,-1};
    const struct { double roll, pitch, yaw, expectedRoll, expectedYaw; int singular; } cases[] = {
        {17,-28,143,17,143,0}, {-32,46,-121,-32,-121,0},
        {20,90,35,0,15,1}, {20,-90,35,0,55,1},
        {0,89.999,10,0,10,0}
    };
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        double desired[9], first[9], second[9], raw[9]; AFTagFRCPose result;
        rawFromOpticalXYZ(cases[i].roll,cases[i].pitch,cases[i].yaw,desired);
        /* Invert the independently specified complete basis transform. */
        multiply(inverse, desired, first); multiply(first,b,second); multiply(second,correction,raw);
        CHECK(AFTagConvertOpticalPoseToFRC(translation,raw,&result));
        matrixNear(result.rotationRowMajor,desired,1e-12);
        near(result.rollDegrees,cases[i].expectedRoll,1e-7);
        near(result.pitchDegrees,cases[i].pitch,2e-6);
        near(result.yawDegrees,cases[i].expectedYaw,1e-7);
        CHECK(result.eulerSingular == cases[i].singular);
    }
}

static void checkInvalid(const double *translation,const double *rotation) {
    AFTagFTCPose ftc,zeroFTC; AFTagFRCPose frc,zeroFRC;
    memset(&ftc,0xa5,sizeof(ftc)); memset(&frc,0xa5,sizeof(frc));
    memset(&zeroFTC,0,sizeof(zeroFTC)); memset(&zeroFRC,0,sizeof(zeroFRC));
    CHECK(!AFTagConvertOpticalPoseToFTC(translation,rotation,&ftc));
    CHECK(!AFTagConvertOpticalPoseToFRC(translation,rotation,&frc));
    CHECK(memcmp(&ftc,&zeroFTC,sizeof(ftc)) == 0);
    CHECK(memcmp(&frc,&zeroFRC,sizeof(frc)) == 0);
}
static void testInvalidDataAndUnchangedInputs(void) {
    const double identity[9] = {1,0,0,0,1,0,0,0,1}, translation[3] = {.2,-.3,2};
    checkInvalid(NULL,identity); checkInvalid(translation,NULL);
    for (int i = 0; i < 3; ++i) {
        double invalid[3]; memcpy(invalid,translation,sizeof(invalid)); invalid[i] = NAN; checkInvalid(invalid,identity);
        invalid[i] = INFINITY; checkInvalid(invalid,identity);
    }
    for (int i = 0; i < 9; ++i) {
        double invalid[9]; memcpy(invalid,identity,sizeof(invalid)); invalid[i] = NAN; checkInvalid(translation,invalid);
        invalid[i] = INFINITY; checkInvalid(translation,invalid);
    }
    double nonpositive[3] = {1,2,0}; checkInvalid(nonpositive,identity); nonpositive[2] = -2; checkInvalid(nonpositive,identity);
    double reflection[9] = {-1,0,0,0,1,0,0,0,1}; checkInvalid(translation,reflection);
    double scaled[9] = {2,0,0,0,2,0,0,0,2}; checkInvalid(translation,scaled);
    double shear[9] = {1,.2,0,0,1,0,0,0,1}; checkInvalid(translation,shear);
    double overflow[3] = {1.7e308,1.7e308,1.7e308}; checkInvalid(overflow,identity);
    CHECK(!AFTagConvertOpticalPoseToFTC(translation,identity,NULL));
    CHECK(!AFTagConvertOpticalPoseToFRC(translation,identity,NULL));
    double originalRotation[9], originalTranslation[3];
    memcpy(originalRotation,identity,sizeof(identity)); memcpy(originalTranslation,translation,sizeof(translation));
    AFTagFTCPose ftc; AFTagFRCPose frc;
    CHECK(AFTagConvertOpticalPoseToFTC(translation,identity,&ftc));
    CHECK(AFTagConvertOpticalPoseToFRC(translation,identity,&frc));
    CHECK(memcmp(originalRotation,identity,sizeof(identity)) == 0);
    CHECK(memcmp(originalTranslation,translation,sizeof(translation)) == 0);
}

int main(void) {
    testTranslationsRangesAndIndependentSignedAngles();
    testActualFTCSDKGoldenAngles();
    testFTCRotationReexpressesBothBases();
    testPhotonVisionTagBasisAndIndependentGoldenAngles();
    testFRCRotationAndSingularity();
    testInvalidDataAndUnchangedInputs();
    puts("PASS: FTC SDK golden branches, signed bearing/elevation, planar range; PhotonVision full tag/camera bases, compound rotations and singularities; invalid-data guards and untouched optical inputs.");
    return 0;
}
