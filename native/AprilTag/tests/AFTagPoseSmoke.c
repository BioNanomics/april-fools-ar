#include "AFTagCore.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static void rotation(double rollDegrees, double pitchDegrees, double yawDegrees, double r[9]) {
    const double d = M_PI / 180;
    double cr = cos(rollDegrees*d), sr = sin(rollDegrees*d), cp = cos(pitchDegrees*d);
    double sp = sin(pitchDegrees*d), cy = cos(yawDegrees*d), sy = sin(yawDegrees*d);
    double value[9] = {cy*cp, cy*sp*sr-sy*cr, cy*sp*cr+sy*sr,
                      sy*cp, sy*sp*sr+cy*cr, sy*sp*cr-cy*sr,
                      -sp, cp*sr, cp*cr};
    memcpy(r, value, sizeof(value));
}

static void project(const double r[9], const double t[3], const AFTagCalibration *k, double pixels[4][2]) {
    const double s[4][2] = {{-1,1}, {1,1}, {1,-1}, {-1,-1}};
    for (int i = 0; i < 4; i++) {
        double x = s[i][0]*k->tagSizeMeters/2, y = s[i][1]*k->tagSizeMeters/2;
        double z = r[6]*x + r[7]*y + t[2];
        pixels[i][0] = k->fx*(r[0]*x+r[1]*y+t[0])/z+k->cx;
        pixels[i][1] = k->fy*(r[3]*x+r[4]*y+t[1])/z+k->cy;
    }
}

static double independentPixelRMS(const AFTagPose *pose, const AFTagCalibration *k, const double corners[4][2]) {
    double projection[4][2], squared = 0;
    project(pose->rotationRowMajor, pose->translation, k, projection);
    for (int i = 0; i < 4; i++) for (int j = 0; j < 2; j++) {
        double delta = projection[i][j]-corners[i][j];
        squared += delta*delta;
    }
    return sqrt(squared/4);
}

static AFTagPose knownPose(double roll, double pitch, double yaw, const double t[3], AFTagCalibration k) {
    double r[9], corners[4][2];
    rotation(roll,pitch,yaw,r); project(r,t,&k,corners);
    AFTagPose pose;
    assert(AFTagCoreEstimatePoseFromCorners(corners,&k,&pose)==AFTagCoreSuccess);
    for (int i=0;i<3;i++) assert(fabs(pose.translation[i]-t[i])<1e-4);
    for (int i=0;i<9;i++) assert(fabs(pose.rotationRowMajor[i]-r[i])<1e-3);
    assert(fabs(pose.eulerDegrees[0]-roll)<0.02);
    assert(fabs(pose.eulerDegrees[1]-pitch)<0.02);
    assert(fabs(pose.eulerDegrees[2]-yaw)<0.02);
    assert(pose.reprojectionRMSEPixels<0.01);
    assert(fabs(pose.reprojectionRMSEPixels-independentPixelRMS(&pose,&k,corners))<1e-12);
    assert(fabs(pose.rangeMeters-hypot(hypot(t[0],t[1]),t[2]))<1e-4);
    assert(fabs(pose.opticalAxisAngleDegrees-atan2(hypot(t[0],t[1]),t[2])*180/M_PI)<0.01);
    double expectedIncidence=acos(fmin(1,fabs((r[2]*t[0]+r[5]*t[1]+r[8]*t[2])/
        hypot(hypot(t[0],t[1]),t[2]))))*180/M_PI;
    assert(fabs(pose.planeAngleDegrees-expectedIncidence)<0.02);
    const double signs[4][2]={{-1,1},{1,1},{1,-1},{-1,-1}};
    for(int i=0;i<4;i++)assert(pose.rotationRowMajor[6]*signs[i][0]*k.tagSizeMeters/2+
        pose.rotationRowMajor[7]*signs[i][1]*k.tagSizeMeters/2+pose.translation[2]>0);
    if (pose.hasSecondPose) {
        assert(isfinite(pose.secondPoseError) && isfinite(pose.poseErrorRatio));
        assert(pose.poseErrorRatio>=0 && pose.poseErrorRatio<=1);
        assert(pose.secondPoseError>=pose.poseError);
    }
    printf("known RPY=(%.0f,%.0f,%.0f) t=(%.2f,%.2f,%.2f) RMS=%.7f candidates=%d ambiguous=%d\n",
           roll,pitch,yaw,t[0],t[1],t[2],pose.reprojectionRMSEPixels,pose.candidateCount,pose.ambiguous);
    return pose;
}

int main(void) {
    AFTagCalibration k={.fx=1400,.fy=1350,.cx=960,.cy=540,.tagSizeMeters=0.1651};
    const double frontal[3]={0,0,1};
    AFTagPose headOn=knownPose(0,0,0,frontal,k);
    assert(!headOn.ambiguous && headOn.planeAngleDegrees<0.02);
    const double oblique[3]={0.12,-0.07,1.2};
    knownPose(12,-28,33,oblique,k);
    knownPose(-24,17,-42,oblique,k);
    const double offAxis[3]={0.2,0.1,1};
    AFTagPose off=knownPose(0,0,0,offAxis,k);
    assert(fabs(off.planeAngleDegrees-off.opticalAxisAngleDegrees)<0.02);
    knownPose(0,0,90,frontal,k);
    const double nearFrontal[3]={0.0001,-0.0001,0.7};
    AFTagPose near=knownPose(0.001,-0.001,0.002,nearFrontal,k);
    assert(!near.ambiguous); // Converging duplicate minima are not ambiguity.

    double r[9], corners[4][2];
    rotation(12,-28,33,r); project(r,oblique,&k,corners);
    const double noise[4][2]={{0.4,-0.2},{-0.3,0.2},{0.1,0.5},{-0.2,-0.4}};
    for(int i=0;i<4;i++)for(int j=0;j<2;j++)corners[i][j]+=noise[i][j];
    AFTagPose noisy;
    assert(AFTagCoreEstimatePoseFromCorners(corners,&k,&noisy)==AFTagCoreSuccess);
    double actualRMS=independentPixelRMS(&noisy,&k,corners);
    assert(actualRMS>0.01 && fabs(actualRMS-noisy.reprojectionRMSEPixels)<1e-12);
    assert(fabs(noisy.poseError-noisy.reprojectionRMSEPixels)>0.001);
    AFTagCalibration doubled=k; doubled.tagSizeMeters*=2;
    AFTagPose scaled;
    assert(AFTagCoreEstimatePoseFromCorners(corners,&doubled,&scaled)==AFTagCoreSuccess);
    for(int i=0;i<3;i++)assert(fabs(scaled.translation[i]-2*noisy.translation[i])<1e-8);
    assert(fabs(scaled.rangeMeters-2*noisy.rangeMeters)<1e-8);
    assert(fabs(scaled.reprojectionRMSEPixels-noisy.reprojectionRMSEPixels)<1e-8);
    assert(fabs(scaled.poseError-4*noisy.poseError)<1e-12);

    AFTagCalibration bad[]={k,k,k,k,k,k};
    bad[0].fx=0; bad[1].fy=-1; bad[2].cx=NAN; bad[3].tagSizeMeters=0;
    bad[4].tagSizeMeters=INFINITY; bad[5].fx=1e300;
    AFTagPose unavailable;
    for(size_t i=0;i<sizeof(bad)/sizeof(bad[0]);i++) {
        memset(&unavailable,0xff,sizeof(unavailable));
        assert(AFTagCoreEstimatePoseFromCorners(corners,&bad[i],&unavailable)==AFTagCoreInvalidInput);
        assert(unavailable.candidateCount==0 && unavailable.translation[2]==0);
    }
    assert(AFTagCoreEstimatePoseFromCorners(corners,NULL,&unavailable)==AFTagCoreInvalidInput);
    double invalid[4][2]={{0,0},{1,0},{2,0},{3,0}};
    assert(AFTagCoreEstimatePoseFromCorners(invalid,&k,&unavailable)==AFTagCoreInvalidInput);
    corners[0][0]=NAN;
    assert(AFTagCoreEstimatePoseFromCorners(corners,&k,&unavailable)==AFTagCoreInvalidInput);
    printf("PASS: known optical poses/Euler/angles, near-frontal ambiguity, independently projected pixel RMS, tag-size scaling, invalid/missing calibration and degenerate corners.\n");
    return 0;
}
