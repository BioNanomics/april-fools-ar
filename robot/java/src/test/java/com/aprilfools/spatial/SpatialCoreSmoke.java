package com.aprilfools.spatial;

public final class SpatialCoreSmoke {
    private static void near(double actual, double expected) {
        if (Math.abs(actual - expected) > 1e-7) throw new AssertionError(actual + " != " + expected);
    }
    private static void rejects(Runnable action) {
        try { action.run(); throw new AssertionError("Expected invalid input to be rejected"); }
        catch (IllegalArgumentException expected) { }
    }
    public static void main(String[] args) {
        System.loadLibrary("af_spatial_core_jni");
        if (SpatialCore.abiVersion() != 1) throw new AssertionError("ABI mismatch");
        double[] origin = {0, 0, 0}, target = {3, 4, 0}, normal = {0, 1, 0};
        double[] distance = SpatialCore.distance(origin, target);
        near(distance[0], 5); near(distance[1], 4); near(distance[2], 3);
        near(SpatialCore.floorHeight(target, origin, normal), 4);
        near(SpatialCore.verticalFoot(target, origin, normal)[1], 0);
        double[] floor = new double[8 * 8 * 3];
        for (int x = 0; x < 8; ++x) for (int z = 0; z < 8; ++z) {
            int i = (x * 8 + z) * 3; floor[i] = x * 0.1; floor[i + 2] = z * 0.1;
        }
        double[] fit = SpatialCore.fitFloor(floor, 0, 0);
        near(fit[1], 0); near(fit[4], 1); near(fit[8], 64);
        // Upstream corner order gives an optical camera-facing, one metre pose.
        double[] pose = SpatialCore.estimateTagPose(new double[]{280,280,360,280,360,200,280,200},
            new double[]{800,800,320,240,0.1});
        near(pose[2], 1); near(pose[12], 1); near(pose[13], 0);
        rejects(() -> SpatialCore.distance(null, target));
        rejects(() -> SpatialCore.distance(new double[]{0, 0}, target));
        rejects(() -> SpatialCore.distance(new double[]{Double.NaN, 0, 0}, target));
        rejects(() -> SpatialCore.floorHeight(target, origin, new double[]{1,0,0}));
        rejects(() -> SpatialCore.fitFloor(new double[6], 0, 0));
        rejects(() -> SpatialCore.estimateTagPose(new double[8], new double[5]));
        System.out.println("JNI numerical consumer and validation passed: " + SpatialCore.version());
    }
}
