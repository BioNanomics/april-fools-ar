import Foundation
import CoreFoundation
import simd

/// Camera orientation and tag pose must come from the same captured AR frame.
struct TagGravityOrientationContext {
    let cameraToWorld: simd_float4x4
    let settings: TagDebugSettings
    let tracking: String
    let frameID: String
    let segmentID: String
    let timestamp: Double
    let frameAgeSeconds: Double
}

enum TagGravityOrientation {
    static func enrich(_ detection: [String: Any], context: TagGravityOrientationContext) -> [String: Any] {
        var result = detection
        let orientation = evaluate(detection, context: context)
        result["gravityOrientation"] = orientation
        var debug = result["debug"] as? [String: Any] ?? [:]
        debug["gravityOrientation"] = orientation
        result["debug"] = debug
        return result
    }

    static func evaluate(_ detection: [String: Any], context: TagGravityOrientationContext) -> [String: Any] {
        var output: [String: Any] = [
            "available": false, "reason": "invalidPose", "tiltFromVerticalDegrees": NSNull(),
            "twistDegrees": NSNull(), "twistAvailable": false, "twistReason": "orientationUnavailable",
            "normalWorld": NSNull(), "upWorld": NSNull(), "worldFromTagRotationRowMajor": NSNull(),
            "source": "tagPose+ARKitGravity", "coordinateFrame": "gravity-aligned-world-y-up",
            "method": "R_world_ARCamera * diag(1,-1,-1) * R_optical_tag",
            "angleConvention": "tilt: unsigned printed-plane departure from vertical, 0 vertical / 90 horizontal; twist: clockwise from upright looking at the printed front, undefined for a horizontal plane",
            "frameId": context.frameID, "segmentId": context.segmentID,
            "timestamp": context.timestamp.isFinite ? context.timestamp as Any : NSNull(),
            "frameAgeSeconds": context.frameAgeSeconds.isFinite ? context.frameAgeSeconds as Any : NSNull(),
            "estimate": true
        ]
        var input = AFSCGravityOrientationInput()
        input.tracking_usable = context.tracking == "normal" ? 1 : 0
        input.frame_id_available = context.frameID.isEmpty || context.segmentID.isEmpty ? 0 : 1
        input.timestamp_s = context.timestamp
        input.frame_age_s = context.frameAgeSeconds
        input.world_from_optical = TagDebugMath.coreWorldFromOptical(context.cameraToWorld)
        input.settings = TagDebugMath.coreMeasurementSettings(context.settings)
        let pose = detection["pose"] as? [String: Any] ?? [:]
        let rotation = numbers(pose["rotationRowMajor"], count: 9)
        // The matrix is authoritative, including at Euler-angle singularities.
        input.pose.orientation_available = rotation == nil ? 0 : 1
        withUnsafeMutableBytes(of: &input.optical_from_tag_rotation.values) { bytes in
            let values = bytes.bindMemory(to: Double.self)
            values[15] = 1
            if let rotation {
                for column in 0..<3 { for row in 0..<3 { values[column*4+row] = rotation[row*3+column] } }
            }
        }
        if let translation = numbers(pose["translation"], count: 3) {
            input.pose.translation_available = 1
            input.pose.translation = AFSCVec3(x: translation[0], y: translation[1], z: translation[2])
            input.pose.range_m = TagDebugMath.coreOptional(hypot(hypot(translation[0], translation[1]), translation[2]))
        }
        input.pose.plane_angle_rad = TagDebugMath.coreOptional(number(pose["planeAngleDegrees"]).map { $0 * .pi / 180 })
        input.pose.reprojection_rms_px = TagDebugMath.coreOptional(number(pose["reprojectionRMSEPixels"]))
        input.pose.decision_margin = TagDebugMath.coreOptional(number(detection["decisionMargin"]))
        input.pose.corrected_bits = TagDebugMath.coreOptional(number(detection["hamming"]))
        if let ambiguous = pose["ambiguous"] as? NSNumber, CFGetTypeID(ambiguous) == CFBooleanGetTypeID() {
            input.pose.ambiguous = ambiguous.boolValue ? 1 : 0
        } else { input.pose.ambiguous = -1 }
        let value = afsc_gravity_orientation(&input)
        guard value.available != 0 else {
            output["reason"] = reason(value.reason)
            return output
        }
        let rotationWorld = withUnsafeBytes(of: value.world_from_tag_rotation.values) { bytes -> [Double] in
            let values = bytes.bindMemory(to: Double.self)
            return (0..<9).map { values[($0 % 3)*4 + $0 / 3] }
        }
        let twist = TagDebugMath.coreValue(value.twist_rad).map { $0 * 180 / .pi }
        output.merge([
            "available": true, "reason": "valid", "tiltFromVerticalDegrees": value.tilt_from_vertical_rad * 180 / .pi,
            "twistDegrees": twist as Any? ?? NSNull(), "twistAvailable": twist != nil,
            "twistReason": twist == nil ? "horizontalTagPlane" : "valid",
            "normalWorld": [value.normal_world.x, value.normal_world.y, value.normal_world.z],
            "upWorld": [value.up_world.x, value.up_world.y, value.up_world.z],
            "worldFromTagRotationRowMajor": rotationWorld
        ]) { _, new in new }
        return output
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private static func numbers(_ value: Any?, count: Int) -> [Double]? {
        guard let values = value as? [Any], values.count == count else { return nil }
        let result = values.compactMap(number)
        return result.count == count ? result : nil
    }
    private static func reason(_ reason: AFSCGravityOrientationReason) -> String {
        switch reason {
        case AFSC_GRAVITY_ORIENTATION_TRACKING_LIMITED: return "trackingLimited"
        case AFSC_GRAVITY_ORIENTATION_STALE_FRAME: return "staleFrame"
        case AFSC_GRAVITY_ORIENTATION_AMBIGUOUS_POSE: return "ambiguousPose"
        case AFSC_GRAVITY_ORIENTATION_TOO_FAR: return "tooFar"
        case AFSC_GRAVITY_ORIENTATION_BAD_ANGLE: return "badAngle"
        case AFSC_GRAVITY_ORIENTATION_LOW_CONFIDENCE_POSE: return "lowConfidencePose"
        default: return "invalidPose"
        }
    }
}
