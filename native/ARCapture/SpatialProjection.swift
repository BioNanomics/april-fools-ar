import Foundation
import CoreGraphics
import simd

/// Native display adapter for the shared optical-camera projection and clipping core.
enum SpatialProjection {
    struct Camera {
        private var core: AFSCProjection
        let viewport: CGRect
        let nearPlaneMeters: Float

        init?(cameraToWorld: simd_float4x4, intrinsics: simd_float3x3, imageSize: CGSize,
              displayTransform: CGAffineTransform, viewportSize: CGSize, nearPlaneMeters: Float = 0.01) {
            var transform = AFSCMat4(), calibration = AFSCIntrinsics()
            // T_world_optical = T_world_ARCamera * diag(1,-1,-1,1).
            withUnsafeMutablePointer(to: &transform.values) { tuple in
                tuple.withMemoryRebound(to: Double.self, capacity: 16) { values in
                    for column in 0..<4 { for row in 0..<4 {
                        values[column * 4 + row] = Double(cameraToWorld[column][row]) * ((column == 1 || column == 2) ? -1 : 1)
                    } }
                }
            }
            withUnsafeMutablePointer(to: &calibration.values) { tuple in
                tuple.withMemoryRebound(to: Double.self, capacity: 9) { values in
                    for column in 0..<3 { for row in 0..<3 { values[column * 3 + row] = Double(intrinsics[column][row]) } }
                }
            }
            let affine = [Double(displayTransform.a), Double(displayTransform.b), Double(displayTransform.c),
                          Double(displayTransform.d), Double(displayTransform.tx), Double(displayTransform.ty)]
            var projection = AFSCProjection()
            guard afsc_projection_init(transform, calibration, affine, Double(imageSize.width), Double(imageSize.height),
                                       Double(viewportSize.width), Double(viewportSize.height), Double(nearPlaneMeters), &projection) == 1 else { return nil }
            self.core = projection
            self.viewport = CGRect(origin: .zero, size: viewportSize)
            self.nearPlaneMeters = nearPlaneMeters
        }

        func point(_ world: SIMD3<Float>) -> CGPoint? {
            var camera = core, result = AFSCVec2()
            guard afsc_project_point(&camera, Self.vector(world), &result) == 1 else { return nil }
            return CGPoint(x: result.x, y: result.y)
        }
        func polygon(_ vertices: [SIMD3<Float>]) -> [CGPoint] {
            guard vertices.count >= 3, vertices.count <= Int(AFSC_MAX_POLYGON_INPUT) else { return [] }
            var camera = core
            let input = vertices.map(Self.vector)
            var output = [AFSCVec2](repeating: AFSCVec2(), count: Int(AFSC_MAX_POLYGON_OUTPUT))
            let count = afsc_project_polygon(&camera, input, input.count, &output, output.count)
            return output.prefix(count).map { CGPoint(x: $0.x, y: $0.y) }
        }
        func segment(from start: SIMD3<Float>, to end: SIMD3<Float>) -> [CGPoint]? {
            var camera = core, output = [AFSCVec2](repeating: AFSCVec2(), count: 2)
            guard afsc_project_segment(&camera, Self.vector(start), Self.vector(end), &output) == 1 else { return nil }
            return output.map { CGPoint(x: $0.x, y: $0.y) }
        }
        private static func vector(_ point: SIMD3<Float>) -> AFSCVec3 {
            AFSCVec3(x: Double(point.x), y: Double(point.y), z: Double(point.z))
        }
    }
}
