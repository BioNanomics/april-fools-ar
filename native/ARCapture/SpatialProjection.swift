import Foundation
import CoreGraphics
import simd

/// Projects fixed AR world geometry through one captured camera and display/zoom transform.
enum SpatialProjection {
    struct Camera {
        private let worldToCamera: simd_float4x4
        private let k: simd_float3x3
        private let imageSize: CGSize
        private let displayTransform: CGAffineTransform
        let viewport: CGRect
        let nearPlaneMeters: Float

        init?(cameraToWorld: simd_float4x4, intrinsics: simd_float3x3, imageSize: CGSize,
              displayTransform: CGAffineTransform, viewportSize: CGSize, nearPlaneMeters: Float = 0.01) {
            let matrices = (0..<4).flatMap { column in (0..<4).map { cameraToWorld[column][$0] } } +
                (0..<3).flatMap { column in (0..<3).map { intrinsics[column][$0] } }
            let affine = [displayTransform.a, displayTransform.b, displayTransform.c,
                          displayTransform.d, displayTransform.tx, displayTransform.ty]
            guard matrices.allSatisfy(\.isFinite), affine.allSatisfy(\.isFinite),
                  imageSize.width.isFinite, imageSize.height.isFinite, viewportSize.width.isFinite, viewportSize.height.isFinite,
                  imageSize.width > 0, imageSize.height > 0, viewportSize.width > 0, viewportSize.height > 0,
                  intrinsics[0][0] > 0, intrinsics[1][1] > 0,
                  nearPlaneMeters.isFinite, nearPlaneMeters > 0,
                  abs(simd_determinant(cameraToWorld)) > 1e-8,
                  abs(displayTransform.a * displayTransform.d - displayTransform.b * displayTransform.c) > 1e-12 else { return nil }
            let inverse = simd_inverse(cameraToWorld)
            guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { inverse[column][$0].isFinite } }) else { return nil }
            self.worldToCamera = inverse; self.k = intrinsics; self.imageSize = imageSize
            self.displayTransform = displayTransform
            self.viewport = CGRect(origin: .zero, size: viewportSize)
            self.nearPlaneMeters = nearPlaneMeters
        }

        /// AR camera looks down -Z with +Y up. Pinhole/depth coordinates use +Z forward, +Y down.
        private func optical(_ world: SIMD3<Float>) -> SIMD3<Float>? {
            guard world.x.isFinite, world.y.isFinite, world.z.isFinite else { return nil }
            let p = worldToCamera * SIMD4<Float>(world, 1)
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite, p.w.isFinite, abs(p.w - 1) < 1e-3 else { return nil }
            return SIMD3<Float>(p.x, -p.y, -p.z)
        }

        private func display(_ optical: SIMD3<Float>) -> CGPoint? {
            guard optical.z >= nearPlaneMeters * (1 - 1e-5) else { return nil }
            let pixelX = Double(k[0][0]) * Double(optical.x) / Double(optical.z) + Double(k[2][0])
            let pixelY = Double(k[1][1]) * Double(optical.y) / Double(optical.z) + Double(k[2][1])
            let normalized = CGPoint(x: pixelX / imageSize.width, y: pixelY / imageSize.height).applying(displayTransform)
            let result = CGPoint(x: normalized.x * viewport.width, y: normalized.y * viewport.height)
            guard result.x.isFinite, result.y.isFinite else { return nil }
            return result
        }

        func point(_ world: SIMD3<Float>) -> CGPoint? { optical(world).flatMap(display) }

        /// Near-plane clipping precedes perspective divide, then the visible viewport clips the polygon.
        func polygon(_ vertices: [SIMD3<Float>]) -> [CGPoint] {
            guard vertices.count >= 3, vertices.count <= 512 else { return [] }
            let cameraVertices = vertices.compactMap(optical)
            guard cameraVertices.count == vertices.count else { return [] }
            var clipped = [SIMD3<Float>]()
            var previous = cameraVertices.last!
            for current in cameraVertices {
                let previousInside = previous.z >= nearPlaneMeters, currentInside = current.z >= nearPlaneMeters
                if previousInside != currentInside {
                    let fraction = (nearPlaneMeters - previous.z) / (current.z - previous.z)
                    var intersection = previous + (current - previous) * fraction
                    intersection.z = nearPlaneMeters
                    clipped.append(intersection)
                }
                if currentInside { clipped.append(current) }
                previous = current
            }
            guard clipped.count >= 3 else { return [] }
            let projected = clipped.compactMap(display)
            guard projected.count == clipped.count else { return [] }
            var result = projected
            // Signed distance is positive inside. This also bounds hit paths and rendering coordinates.
            let edges: [(CGPoint) -> CGFloat] = [
                { $0.x }, { viewport.width - $0.x }, { $0.y }, { viewport.height - $0.y }
            ]
            for distance in edges {
                guard let last = result.last else { return [] }
                var output = [CGPoint](), previous = last
                for current in result {
                    let a = distance(previous), b = distance(current)
                    if (a >= 0) != (b >= 0) {
                        let fraction = a / (a - b)
                        output.append(CGPoint(x: previous.x + (current.x - previous.x) * fraction,
                                              y: previous.y + (current.y - previous.y) * fraction))
                    }
                    if b >= 0 { output.append(current) }
                    previous = current
                }
                result = output
            }
            return result.count >= 3 && result.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) ? result : []
        }

        /// Visible segment endpoints. Markers should separately project the original world endpoints.
        func segment(from start: SIMD3<Float>, to end: SIMD3<Float>) -> [CGPoint]? {
            guard var a = optical(start), var b = optical(end) else { return nil }
            guard a.z >= nearPlaneMeters || b.z >= nearPlaneMeters else { return nil }
            if a.z < nearPlaneMeters {
                a += (b - a) * ((nearPlaneMeters - a.z) / (b.z - a.z)); a.z = nearPlaneMeters
            } else if b.z < nearPlaneMeters {
                b += (a - b) * ((nearPlaneMeters - b.z) / (a.z - b.z)); b.z = nearPlaneMeters
            }
            guard let p = display(a), let q = display(b) else { return nil }
            let dx = q.x - p.x, dy = q.y - p.y
            var low: CGFloat = 0, high: CGFloat = 1
            for (direction, offset) in [(-dx, p.x), (dx, viewport.width - p.x), (-dy, p.y), (dy, viewport.height - p.y)] {
                if abs(direction) < 1e-12 { if offset < 0 { return nil }; continue }
                let ratio = offset / direction
                if direction < 0 { low = max(low, ratio) } else { high = min(high, ratio) }
                if low > high { return nil }
            }
            let points = [CGPoint(x: p.x + low * dx, y: p.y + low * dy), CGPoint(x: p.x + high * dx, y: p.y + high * dy)]
            return points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) ? points : nil
        }
    }
}
