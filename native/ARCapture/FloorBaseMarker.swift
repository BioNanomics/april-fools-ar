import Foundation
import simd

/// A small world-anchored footprint on the exact floor datum used by a height vector.
enum FloorBaseMarker {
    enum State: String { case level, tilted, unknown }
    struct Marker {
        let center: SIMD3<Float>
        let corners: [SIMD3<Float>]
        let state: State
        let sideMeters: Double
    }

    static func make(center: SIMD3<Float>, floor: SpatialPlane, sideMeters: Double = 0.30) -> Marker? {
        // Renderer geometry is Float: reject side lengths that underflow or overflow its math.
        let half = Float(sideMeters / 2)
        guard half.isFinite, half > 0, (Float(sideMeters) * Float(sideMeters)).isFinite else { return nil }
        var quad = AFSCQuad()
        guard afsc_floor_marker(SpatialMeasurementMath.coreVector(center), SpatialMeasurementMath.corePlane(floor),
                                sideMeters, &quad) == AFSC_GEOMETRY_OK else { return nil }
        let corners = [quad.p0, quad.p1, quad.p2, quad.p3].map(SpatialMeasurementMath.swiftVector)
        guard corners.allSatisfy(SpatialMeasurementMath.finite), (0..<4).allSatisfy({
            // Conversion must not collapse a valid double-precision edge in the Float renderer.
            let edge = SpatialMeasurementMath.distance(from: corners[$0], to: corners[($0 + 1) % 4]).distance_meters
            return edge.isFinite && edge > 0
        }) else { return nil }
        let state: State
        if let tilt = floor.effectiveTiltDegrees, tilt.isFinite { state = tilt <= 0.5 + 1e-6 ? .level : .tilted }
        else { state = .unknown }
        return Marker(center: center, corners: corners, state: state, sideMeters: sideMeters)
    }
}
