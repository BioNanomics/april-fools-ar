import Foundation
import CoreGraphics

/// Full-image playback orientation; the camera pixels and calibration stay unchanged.
/// Strip viewport cropping/zoom from ARKit's sensor-to-display mapping and retain
/// only its orthogonal rotation. A movie's orientation is fixed at its first frame.
enum VideoOrientation {
    static func playbackTransform(manifest: [String: Any], firstFrame: [String: Any]?) -> [Double]? {
        if let content = manifest["videoContent"] as? [String: Any],
           let stored = numbers(content["playbackTransform"], count: 6), valid(stored) { return stored }
        guard let frame = firstFrame else { return nil }
        return playbackTransform(frame: frame)
    }

    static func playbackTransform(frame: [String: Any]) -> [Double]? {
        guard let width = number(frame["imageWidth"]), let height = number(frame["imageHeight"]),
              width > 0, height > 0, width <= 65535, height <= 65535 else { return nil }
        if let mapping = numbers(frame["displayTransform"], count: 6) {
            let a = mapping[0], b = mapping[1], c = mapping[2], d = mapping[3]
            let scale = max(abs(a), abs(b), abs(c), abs(d))
            guard scale > 0 else { return nil }
            let tolerance = scale * 1e-5
            if abs(b) <= tolerance && abs(c) <= tolerance {
                if a > tolerance && d > tolerance { return [1, 0, 0, 1, 0, 0] }
                if a < -tolerance && d < -tolerance { return [-1, 0, 0, -1, width, height] }
            }
            if abs(a) <= tolerance && abs(d) <= tolerance {
                if b > tolerance && c < -tolerance { return [0, 1, -1, 0, height, 0] }
                if b < -tolerance && c > tolerance { return [0, -1, 1, 0, 0, width] }
            }
            // Do not silently flatten a reflection or arbitrary transform.
            return nil
        }
        // Old portrait records may lack a display mapping. Raw ARKit rear-camera
        // buffers are landscape; these two UIKit orientation values are explicit.
        switch (frame["interfaceOrientation"] as? NSNumber)?.intValue {
        case 1: return [0, 1, -1, 0, height, 0]
        case 2: return [0, -1, 1, 0, 0, width]
        default: return nil
        }
    }

    static func affine(_ values: [Double]) -> CGAffineTransform? {
        guard valid(values) else { return nil }
        return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }

    private static func valid(_ values: [Double]) -> Bool {
        values.count == 6 && values.allSatisfy(\.isFinite)
            && abs(values[0] * values[3] - values[1] * values[2] - 1) < 1e-6
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    private static func numbers(_ value: Any?, count: Int) -> [Double]? {
        guard let raw = value as? [Any], raw.count == count else { return nil }
        let result = raw.compactMap(number)
        return result.count == count ? result : nil
    }
}
