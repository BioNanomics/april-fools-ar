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
        var pose = AFSCPoseObservation()
        if let dictionary = detection["pose"] as? [String: Any], let translation = vector(dictionary["translation"], count: 3) {
            pose.translation_available = 1
            pose.translation = TagDebugMath.coreVector(translation)
        }
        let depth = detection["depth"] as? [String: Any] ?? [:]
        var depthObservation = TagDebugMath.coreDepthObservation(depth: scalar(depth["centerDepthMeters"]),
                                                                 confidence: scalar(depth["centerConfidence"]))
        let center = vector(detection["center"], count: 2)
        var intrinsics = TagDebugMath.coreIntrinsics(context.intrinsics)
        let ranges = afsc_camera_ranges(&pose, &depthObservation, &intrinsics, center == nil ? 0 : 1,
                                       AFSCVec2(x: center?[0] ?? 0, y: center?[1] ?? 0))
        result["tagDepthZMeters"] = TagDebugMath.coreValue(ranges.pose_z_m) as Any? ?? NSNull()
        result["tagRangeMeters"] = TagDebugMath.coreValue(ranges.pose_range_m) as Any? ?? NSNull()
        result["tagAvailable"] = ranges.pose_range_m.available != 0
        result["tagReason"] = reason(ranges.pose_reason)
        result["lidarDepthZMeters"] = TagDebugMath.coreValue(ranges.depth_z_m) as Any? ?? NSNull()
        result["lidarRangeMeters"] = TagDebugMath.coreValue(ranges.depth_range_m) as Any? ?? NSNull()
        result["lidarAvailable"] = ranges.depth_range_m.available != 0
        result["lidarReason"] = reason(ranges.depth_reason)
        result["distanceDeltaMeters"] = TagDebugMath.coreValue(ranges.range_difference_m) as Any? ?? NSNull()
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
    private static func reason(_ value: AFSCRangeReason) -> String {
        switch value {
        case AFSC_RANGE_VALID: return "valid"
        case AFSC_RANGE_MISSING_DEPTH: return "missingDepth"
        case AFSC_RANGE_POSE_UNAVAILABLE: return "poseUnavailable"
        case AFSC_RANGE_INVALID_CONFIDENCE: return "invalidConfidence"
        case AFSC_RANGE_INVALID_INTRINSICS: return "invalidIntrinsics"
        case AFSC_RANGE_INVALID_CENTER: return "invalidCenter"
        default: return "invalidRange"
        }
    }
}
