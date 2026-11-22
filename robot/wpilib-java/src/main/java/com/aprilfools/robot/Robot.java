package com.aprilfools.robot;
import com.aprilfools.spatial.SpatialCore;
import org.wpilib.framework.TimedRobot;

public final class Robot extends TimedRobot {
    public Robot() {
        System.loadLibrary("af_spatial_core_jni");
        double[] distance = SpatialCore.distance(new double[]{0, 0, 0}, new double[]{3, 4, 0});
        System.out.println("AFSpatialCore distance: " + distance[0] + " m");
    }
}
