package com.aprilfools.spatial;

/** Stateless C ABI bridge shared by desktop, WPILib and Android. Metres unless noted.
 * Inputs are copied during each call, arrays must have their exact documented size,
 * and invalid/nonfinite geometry throws IllegalArgumentException. No native handles.
 * Load af_spatial_core_jni via the platform's native library loader before use.
 */
public final class SpatialCore {
    private SpatialCore() {}
    public static native int abiVersion();
    public static native String version();
    /** Each point is [x,y,z]; result is [distance,signed vertical,horizontal]. */
    public static native double[] distance(double[] start, double[] end);
    /** All vectors are [x,y,z], +Y up. Result is the gravity-vertical foot [x,y,z]. */
    public static native double[] verticalFoot(double[] target, double[] planeOrigin, double[] planeNormal);
    /** Geometric height above a floor, with the core's 0..30 m/normal checks.
     * This is geometry only: callers must apply tracking and observation-quality policy.
     */
    public static native double floorHeight(double[] target, double[] planeOrigin, double[] planeNormal);
    /** xyz contains 32..512 triples. Result: origin xyz, normal xyz, tilt radians,
     * sample count, inlier count, RMS metres. */
    public static native double[] fitFloor(double[] xyz, double referenceX, double referenceZ);
    /** corners: 8 ordered AprilTag corner coordinates in original image pixels.
     * calibration: [fx,fy,cx,cy,tagEdgeMetres]. Result: translation xyz (optical axes),
     * rotation (9 row-major), range, reprojection RMS pixels, object-space pose error,
     * candidate count, ambiguous (0/1), plane angle degrees. No pose throws.
     */
    public static native double[] estimateTagPose(double[] corners, double[] calibration);
}
