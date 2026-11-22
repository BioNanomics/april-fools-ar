import Foundation
import CoreFoundation
import simd

struct TagCameraRangesContext {
    let intrinsics: simd_float3x3
    let frameID: String
    let segmentID: String
    let timestamp: Double
}

/// Diagnostic camera distances only. Floor selection and pose-quality coloring are independent.
enum TagCameraRanges {
    static func enrich(_ detection: [String: Any], context: TagCameraRangesContext) -> [String: Any] {
        var result = detection
        let ranges = evaluate(detection, context: context)
        result["cameraRanges"] = ranges
        var debug = result["debug"] as? [String: Any] ?? [:]
        debug["cameraRanges"] = ranges
        result["debug"] = debug
        return result
    }

    static func evaluate(_ detection: [String: Any], context: TagCameraRangesContext) -> [String: Any] {
        var result: [String: Any] = ["lidarRangeMeters": NSNull(), "tagRangeMeters": NSNull(), "distanceDeltaMeters": NSNull(),
            "lidarDepthZMeters": NSNull(), "tagDepthZMeters": NSNull(), "lidarAvailable": false, "tagAvailable": false,
            "lidarReason": "missingDepth", "tagReason": "poseUnavailable", "frameId": context.frameID,
            "segmentId": context.segmentID, "timestamp": context.timestamp.isFinite ? context.timestamp as Any : NSNull(),
            "coordinateFrame": "camera-optical-x-right-y-down-z-forward",
            "rangeConvention": "Euclidean camera-to-center distance; optical-axis Z is reported separately"]
        if let pose = detection["pose"] as? [String: Any], let translation = vector(pose["translation"], count: 3), translation[2] > 0 {
            result["tagDepthZMeters"] = translation[2]
            if let range = length(translation) {
                result["tagRangeMeters"] = range; result["tagAvailable"] = true; result["tagReason"] = "valid"
            } else { result["tagReason"] = "invalidRange" }
        }
        let depth = detection["depth"] as? [String: Any] ?? [:]
        guard let z = scalar(depth["centerDepthMeters"]), z > 0 else { return result }
        guard let confidence = scalar(depth["centerConfidence"]), [1.0, 2.0].contains(confidence) else {
            result["lidarReason"] = "invalidConfidence"; return result
        }
        // A valid sample's axial depth remains available even if camera-ray geometry is malformed.
        result["lidarDepthZMeters"] = z
        let k = context.intrinsics
        let fx = Double(k.columns.0.x), fy = Double(k.columns.1.y)
        let cx = Double(k.columns.2.x), cy = Double(k.columns.2.y)
        guard (0..<3).allSatisfy({ column in (0..<3).allSatisfy { k[column][$0].isFinite } }), fx > 0, fy > 0 else {
            result["lidarReason"] = "invalidIntrinsics"; return result
        }
        guard let center = vector(detection["center"], count: 2), center[0] >= 0, center[1] >= 0 else {
            result["lidarReason"] = "invalidCenter"; return result
        }
        let optical = [(center[0]-cx)/fx*z, (center[1]-cy)/fy*z, z]
        guard let range = length(optical) else { result["lidarReason"] = "invalidRange"; return result }
        result["lidarRangeMeters"] = range; result["lidarAvailable"] = true; result["lidarReason"] = "valid"
        if result["tagAvailable"] as? Bool == true, let tagRange = scalar(result["tagRangeMeters"]), tagRange > 0 {
            let delta = abs(range-tagRange)
            if delta.isFinite { result["distanceDeltaMeters"] = delta }
        }
        return result
    }

    private static func scalar(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func vector(_ raw: Any?, count: Int) -> [Double]? {
        guard let values = raw as? [Any], values.count == count else { return nil }
        let numbers = values.compactMap(scalar)
        return numbers.count == count ? numbers : nil
    }
    private static func length(_ values: [Double]) -> Double? {
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        let range = hypot(hypot(values[0], values[1]), values[2])
        return range.isFinite && range > 0 ? range : nil
    }
}
