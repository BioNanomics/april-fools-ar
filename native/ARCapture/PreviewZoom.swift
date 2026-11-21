import Foundation
import CoreGraphics

/// Preview geometry only; captured pixels, calibration, and camera poses keep their original units.
enum PreviewZoom {
    static let minimum = 1.0
    static let maximum = 4.0

    static func clamped(_ value: Double) throws -> Double {
        guard value.isFinite else { throw ZoomError.nonFinite }
        return min(maximum, max(minimum, value))
    }
    static func normalizedTransform(for zoom: Double) -> CGAffineTransform {
        let factor = CGFloat((try? clamped(zoom)) ?? minimum)
        return CGAffineTransform(a: factor, b: 0, c: 0, d: factor, tx: (1-factor)/2, ty: (1-factor)/2)
    }
    /// Applies the centered zoom after ARKit's original sensor-to-viewport transform.
    static func displayTransform(base: CGAffineTransform, zoom: Double) -> CGAffineTransform {
        let centered = normalizedTransform(for: zoom)
        let factor = centered.a
        return CGAffineTransform(a: base.a * factor, b: base.b * factor,
            c: base.c * factor, d: base.d * factor,
            tx: base.tx * factor + centered.tx, ty: base.ty * factor + centered.ty)
    }
    private enum ZoomError: LocalizedError {
        case nonFinite
        var errorDescription: String? { "Display zoom must be a finite number." }
    }
}
