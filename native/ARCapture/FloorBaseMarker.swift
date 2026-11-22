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
        guard SpatialMeasurementMath.finite(center), SpatialMeasurementMath.finite(floor.origin),
              SpatialMeasurementMath.finite(floor.normal), sideMeters.isFinite, sideMeters > 0 else { return nil }
        let length = simd_length(floor.normal), half = Float(sideMeters / 2)
        guard length.isFinite, length > 1e-6, half.isFinite, half > 0,
              abs(floor.normal.y) / length >= 0.8 else { return nil }
        var normal = floor.normal / length
        if normal.y < 0 { normal = -normal }
        guard abs(simd_dot(normal, center-floor.origin)) <= 0.0001 else { return nil }
        // Project a fixed world axis onto the floor. No camera direction enters this basis.
        let projectedX = SIMD3<Float>(1, 0, 0) - normal * normal.x
        let u = simd_normalize(projectedX), v = simd_normalize(simd_cross(normal, u))
        guard SpatialMeasurementMath.finite(u), SpatialMeasurementMath.finite(v) else { return nil }
        let corners = [center-u*half-v*half, center+u*half-v*half,
                       center+u*half+v*half, center-u*half+v*half]
        guard corners.allSatisfy(SpatialMeasurementMath.finite),
              (0..<4).allSatisfy({
                  let edge = simd_length(corners[($0+1) % 4]-corners[$0])
                  return edge.isFinite && edge > 0
              }) else { return nil }
        let state: State
        if let tilt = floor.effectiveTiltDegrees, tilt.isFinite { state = tilt <= 0.5 + 1e-6 ? .level : .tilted }
        else { state = .unknown }
        return Marker(center: center, corners: corners, state: state, sideMeters: sideMeters)
    }
}
