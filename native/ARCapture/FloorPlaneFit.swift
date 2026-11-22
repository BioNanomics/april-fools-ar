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

    private struct Point { let x: Double, y: Double, z: Double }
    private struct Model {
        let a: Double, b: Double, c: Double
        func residual(_ point: Point) -> Double { abs(point.y - (a*point.x + b*point.z + c)) }
        var tiltDegrees: Double { atan(hypot(a, b)) * 180 / .pi }
    }
    private static let minimumSamples = 32
    private static let maximumSamples = 512
    private static let inlierTolerance = 0.04
    private static let maximumRMS = 0.03
    private static let maximumTilt = 20.0

    /// Fits y = a*x + b*z + c, returning an upward normal and fitted height at referenceXZ.
    /// Returns nil for unknown/unsupported geometry instead of assuming the floor has zero tilt.
    static func fit(points: [SIMD3<Float>], referenceXZ: SIMD2<Float>) -> Result? {
        guard (minimumSamples...maximumSamples).contains(points.count), referenceXZ.x.isFinite, referenceXZ.y.isFinite,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return nil }
        // Local coordinates keep the solve stable after the AR world origin has moved far from the patch.
        let referenceX = Double(referenceXZ.x), referenceZ = Double(referenceXZ.y)
        let baselineY = points.reduce(0.0) { $0 + Double($1.y) } / Double(points.count)
        let local = points.map { Point(x: Double($0.x)-referenceX, y: Double($0.y)-baselineY, z: Double($0.z)-referenceZ) }
        let requiredInliers = max(24, Int(ceil(Double(local.count)*0.65)))
        var bestInliers = [Int](), bestSquaredError = Double.infinity
        var random: UInt64 = 0xA9F1045D2B76C831
        func nextIndex() -> Int {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return Int((random >> 16) % UInt64(local.count))
        }
        // Fixed seed and hypothesis budget make replay deterministic and bound per-frame CPU use.
        for _ in 0..<128 {
            let i = nextIndex(), j = nextIndex(), k = nextIndex()
            guard i != j, i != k, j != k, let model = through(local[i], local[j], local[k]), model.tiltDegrees <= maximumTilt else { continue }
            var inliers = [Int](), error = 0.0
            for index in local.indices {
                let residual = model.residual(local[index])
                if residual <= inlierTolerance { inliers.append(index); error += residual*residual }
            }
            if inliers.count > bestInliers.count || (inliers.count == bestInliers.count && error < bestSquaredError) {
                bestInliers = inliers; bestSquaredError = error
            }
        }
        guard bestInliers.count >= requiredInliers else { return nil }
        // Refine consensus, then reclassify a bounded number of times without pulling gross outliers into the fit.
        var inliers = bestInliers
        for _ in 0..<3 {
            guard let model = leastSquares(inliers.map { local[$0] }), model.tiltDegrees <= maximumTilt else { return nil }
            let refined = local.indices.filter { model.residual(local[$0]) <= inlierTolerance }
            guard refined.count >= requiredInliers else { return nil }
            if refined == inliers { break }
            inliers = refined
        }
        guard let model = leastSquares(inliers.map { local[$0] }), model.tiltDegrees.isFinite, model.tiltDegrees <= maximumTilt else { return nil }
        let rms = sqrt(inliers.reduce(0.0) { sum, index in
            let residual = model.residual(local[index]); return sum + residual*residual
        } / Double(inliers.count))
        let fittedY = baselineY + model.c
        let length = hypot(hypot(model.a, model.b), 1)
        let normal = SIMD3<Float>(Float(-model.a/length), Float(1/length), Float(-model.b/length))
        let origin = SIMD3<Float>(referenceXZ.x, Float(fittedY), referenceXZ.y)
        guard rms.isFinite, rms <= maximumRMS, fittedY.isFinite,
              normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
              origin.x.isFinite, origin.y.isFinite, origin.z.isFinite else { return nil }
        return Result(normal: normal, origin: origin, tiltDegrees: model.tiltDegrees,
                      sampleCount: local.count, inlierCount: inliers.count, rmsMeters: rms)
    }

    private static func through(_ p: Point, _ q: Point, _ r: Point) -> Model? {
        let dx1 = q.x-p.x, dz1 = q.z-p.z, dy1 = q.y-p.y
        let dx2 = r.x-p.x, dz2 = r.z-p.z, dy2 = r.y-p.y
        let determinant = dx1*dz2-dx2*dz1
        guard determinant.isFinite, abs(determinant) > 1e-8 else { return nil }
        let a = (dy1*dz2-dy2*dz1)/determinant, b = (dx1*dy2-dx2*dy1)/determinant
        let c = p.y-a*p.x-b*p.z
        return [a, b, c].allSatisfy(\.isFinite) ? Model(a: a, b: b, c: c) : nil
    }

    private static func leastSquares(_ points: [Point]) -> Model? {
        guard points.count >= 24 else { return nil }
        let count = Double(points.count)
        let meanX = points.reduce(0.0) { $0+$1.x }/count
        let meanY = points.reduce(0.0) { $0+$1.y }/count
        let meanZ = points.reduce(0.0) { $0+$1.z }/count
        var xx = 0.0, zz = 0.0, xz = 0.0, xy = 0.0, zy = 0.0
        for point in points {
            let x = point.x-meanX, y = point.y-meanY, z = point.z-meanZ
            xx += x*x; zz += z*z; xz += x*z; xy += x*y; zy += z*y
        }
        let trace = xx+zz, discriminant = hypot(xx-zz, 2*xz)
        let minimumVariance = (trace-discriminant)/(2*count)
        let maximumVariance = (trace+discriminant)/(2*count)
        let determinant = xx*zz-xz*xz
        // Require about 0.5 m of uniformly sampled width along the patch's narrow principal axis.
        guard trace.isFinite, determinant.isFinite, determinant > 0, minimumVariance >= 0.0225,
              maximumVariance.isFinite, minimumVariance/maximumVariance >= 0.0025 else { return nil }
        let a = (xy*zz-zy*xz)/determinant, b = (zy*xx-xy*xz)/determinant
        let c = meanY-a*meanX-b*meanZ
        return [a, b, c].allSatisfy(\.isFinite) ? Model(a: a, b: b, c: c) : nil
    }
}
