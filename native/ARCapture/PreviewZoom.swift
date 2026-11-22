import Foundation
import CoreGraphics
import UIKit

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
    /// ARKit supplies a quarter-turn plus centered aspect-fill crop. Read the rotation from its
    /// source-image axes so depth/confidence previews follow the same orientation as the camera.
    static func imageOrientation(for display: CGAffineTransform) -> UIImage.Orientation? {
        let values = [display.a, display.b, display.c, display.d, display.tx, display.ty]
        guard values.allSatisfy(\.isFinite) else { return nil }
        let tolerance = max(1, values.prefix(4).map(abs).max() ?? 1) * 1e-6
        if abs(display.b) <= tolerance && abs(display.c) <= tolerance {
            if display.a > tolerance && display.d > tolerance { return .up }
            if display.a < -tolerance && display.d < -tolerance { return .down }
        }
        if abs(display.a) <= tolerance && abs(display.d) <= tolerance {
            if display.b > tolerance && display.c < -tolerance { return .right }
            if display.b < -tolerance && display.c > tolerance { return .left }
        }
        return nil // Reflections, shears and degenerate inputs are not valid camera quarter-turns.
    }
    private enum ZoomError: LocalizedError {
        case nonFinite
        var errorDescription: String? { "Display zoom must be a finite number." }
    }
}
