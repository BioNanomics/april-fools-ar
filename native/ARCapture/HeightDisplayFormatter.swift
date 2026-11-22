import Foundation

/// Presentation only. Recorded geometry and height values remain in meters.
enum HeightDisplayFormatter {
    static func string(meters: Double, showImperial: Bool = true) -> String? {
        guard meters.isFinite, meters >= 0, (meters * 1000).isFinite else { return nil }
        let value = meters == 0 ? 0.0 : meters
        let centimeters = (value * 1000).rounded(.toNearestOrAwayFromZero) / 10
        let locale = Locale(identifier: "en_US_POSIX")
        let metric = String(format: "%.1f cm", locale: locale, centimeters)
        guard showImperial else { return metric }
        // Round the complete distance first, then split, so a 12.0-inch result carries into feet.
        let tenths = (value / 0.0254 * 10).rounded(.toNearestOrAwayFromZero)
        guard tenths.isFinite, tenths >= 0, tenths <= 9_007_199_254_740_991 else { return nil }
        let totalTenths = Int(tenths)
        let feet = totalTenths / 120, inches = Double(totalTenths % 120) / 10
        let inchText = String(format: "%.1f", locale: locale, inches)
        return "\(metric) (\(feet) ft \(inchText) in)"
    }
}
