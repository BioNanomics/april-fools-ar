import ARKit
import CoreVideo
import simd

/// Bounded, same-frame LiDAR samples inside the selected floor footprint.
/// Horizontal ARPlaneAnchor rotations cannot themselves measure physical floor slope.
enum FloorDepthSampler {
    static func samples(frame: ARFrame, plane: SpatialPlane, maximumCount: Int = 512) -> [SIMD3<Float>] {
        guard let depth = frame.sceneDepth else { return [] }
        return samples(depth: depth.depthMap, confidence: depth.confidenceMap,
            intrinsics: frame.camera.intrinsics, cameraToWorld: frame.camera.transform,
            imageSize: CGSize(width: CVPixelBufferGetWidth(frame.capturedImage), height: CVPixelBufferGetHeight(frame.capturedImage)),
            plane: plane, maximumCount: maximumCount)
    }

    static func samples(depth: CVPixelBuffer, confidence: CVPixelBuffer?, intrinsics: simd_float3x3,
                        cameraToWorld: simd_float4x4, imageSize: CGSize, plane: SpatialPlane,
                        maximumCount: Int = 512) -> [SIMD3<Float>] {
        guard let confidence, CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetWidth(confidence) == CVPixelBufferGetWidth(depth),
              CVPixelBufferGetHeight(confidence) == CVPixelBufferGetHeight(depth),
              imageSize.width.isFinite, imageSize.height.isFinite, imageSize.width > 0, imageSize.height > 0,
              plane.vertices.count >= 3, plane.vertices.count <= 512,
              plane.vertices.allSatisfy(SpatialMeasurementMath.finite), SpatialMeasurementMath.finite(plane.origin),
              (0..<3).allSatisfy({ c in (0..<3).allSatisfy { intrinsics[c][$0].isFinite } }),
              (0..<4).allSatisfy({ c in (0..<4).allSatisfy { cameraToWorld[c][$0].isFinite } }),
              intrinsics[0][0] > 0, intrinsics[1][1] > 0 else { return [] }
        guard CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let depths = CVPixelBufferGetBaseAddress(depth), let confidences = CVPixelBufferGetBaseAddress(confidence) else { return [] }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        guard width > 0, height > 0 else { return [] }
        let limit = max(1, min(1024, maximumCount))
        let stride = max(1, Int(ceil(sqrt(Double(width * height) / 1600))))
        let fx = intrinsics[0][0], fy = intrinsics[1][1], cx = intrinsics[2][0], cy = intrinsics[2][1]
        let lowX = plane.vertices.map(\.x).min()!, highX = plane.vertices.map(\.x).max()!
        let lowZ = plane.vertices.map(\.z).min()!, highZ = plane.vertices.map(\.z).max()!
        var accepted = [SIMD3<Float>]()
        accepted.reserveCapacity(1600)
        for y in Swift.stride(from: stride / 2, to: height, by: stride) {
            let depthRow = depths.advanced(by: y * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)
            let confidenceRow = confidences.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
            for x in Swift.stride(from: stride / 2, to: width, by: stride) {
                let z = depthRow[x]
                // Fit nearby floor samples; distant raw capture remains available for other diagnostics.
                guard confidenceRow[x] == 2, z.isFinite, z >= 0.1, z <= 5 else { continue }
                let u = Float((Double(x) + 0.5) / Double(width) * imageSize.width)
                let v = Float((Double(y) + 0.5) / Double(height) * imageSize.height)
                let world4 = cameraToWorld * SIMD4<Float>((u-cx)/fx*z, -(v-cy)/fy*z, -z, 1)
                let world = SIMD3<Float>(world4.x, world4.y, world4.z)
                guard SpatialMeasurementMath.finite(world), abs(world4.w-1) < 0.001,
                      abs(world.y-plane.origin.y) <= 0.5,
                      world.x >= lowX, world.x <= highX, world.z >= lowZ, world.z <= highZ,
                      contains(world, polygon: plane.vertices) else { continue }
                accepted.append(world)
            }
        }
        guard accepted.count > limit else { return accepted }
        // Evenly retain points across the entire scan, rather than favoring one image edge.
        return (0..<limit).map { accepted[$0 * accepted.count / limit] }
    }

    private static func contains(_ point: SIMD3<Float>, polygon: [SIMD3<Float>]) -> Bool {
        var inside = false
        var previous = polygon.last!
        for current in polygon {
            if (current.z > point.z) != (previous.z > point.z) {
                let crossingX = (previous.x-current.x) * (point.z-current.z) / (previous.z-current.z) + current.x
                if point.x < crossingX { inside.toggle() }
            }
            previous = current
        }
        return inside
    }
}
