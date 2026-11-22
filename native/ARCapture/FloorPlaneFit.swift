import Foundation
import simd

/// A bounded, robust fit of observed depth points; an AR horizontal-anchor normal is not a tilt observation.
enum FloorPlaneFit {
    struct Result {
        let normal: SIMD3<Float>
        let origin: SIMD3<Float>
        let tiltDegrees: Double
        let sampleCount: Int
        let inlierCount: Int
        let rmsMeters: Double
    }

    /// Fits y = a*x + b*z + c in the portable spatial core, returning an upward normal.
    /// Returns nil for unknown/unsupported geometry instead of assuming the floor has zero tilt.
    static func fit(points: [SIMD3<Float>], referenceXZ: SIMD2<Float>) -> Result? {
        // Bound the adapter allocation as well as the core's fixed-size working storage.
        guard (32...512).contains(points.count) else { return nil }
        let input = points.map(SpatialMeasurementMath.coreVector)
        var fit = AFSCFloorFit()
        let status = input.withUnsafeBufferPointer {
            afsc_floor_fit($0.baseAddress, $0.count,
                           AFSCVec2(x: Double(referenceXZ.x), y: Double(referenceXZ.y)), &fit)
        }
        guard status == AFSC_GEOMETRY_OK else { return nil }
        let normal = SpatialMeasurementMath.swiftVector(fit.plane.normal)
        let origin = SpatialMeasurementMath.swiftVector(fit.plane.origin)
        guard SpatialMeasurementMath.finite(normal), SpatialMeasurementMath.finite(origin) else { return nil }
        return Result(normal: normal, origin: origin, tiltDegrees: fit.tilt_radians * 180 / .pi,
                      sampleCount: Int(fit.sample_count), inlierCount: Int(fit.inlier_count), rmsMeters: fit.rms_meters)
    }
}
