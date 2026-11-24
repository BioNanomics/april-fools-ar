import Foundation
import simd

/// Immutable input from the exact AR frame analyzed by AprilTag, including its confirmed floor datum.
struct TagFloorHeightContext {
    let floor: SpatialPlane?
    let cameraToWorld: simd_float4x4
    let intrinsics: simd_float3x3
    let settings: TagDebugSettings
    let tracking: String
    let frameID: String
    let segmentID: String
    let timestamp: Double
    let frameAgeSeconds: Double
}

enum TagFloorHeight {
    static func enrich(_ detection: [String: Any], context: TagFloorHeightContext) -> [String: Any] {
        var result = detection
        let height = evaluate(detection, context: context)
        result["floorHeight"] = height
        var debug = result["debug"] as? [String: Any] ?? [:]
        debug["floorHeight"] = height
        result["debug"] = debug
        return result
    }

    static func evaluate(_ detection: [String: Any], context: TagFloorHeightContext) -> [String: Any] {
        var output: [String: Any] = ["available": false, "meters": NSNull(), "source": "unavailable",
            "reason": "floorNotSelected", "floorId": context.floor?.id as Any? ?? NSNull(), "frameId": context.frameID,
            "segmentId": context.segmentID, "timestamp": context.timestamp.isFinite ? context.timestamp as Any : NSNull(),
            "frameAgeSeconds": context.frameAgeSeconds.isFinite ? context.frameAgeSeconds as Any : NSNull(),
            "method": "gravity-vertical intersection with an operator-confirmed floor", "estimate": true]
        var input = AFSCFloorHeightInput()
        input.floor_available = context.floor == nil ? 0 : 1
        input.same_segment = context.floor?.segmentID == context.segmentID ? 1 : 0
        input.tracking_usable = context.tracking == "normal" ? 1 : 0
        input.frame_id_available = context.frameID.isEmpty ? 0 : 1
        input.timestamp_s = context.timestamp
        input.frame_age_s = context.frameAgeSeconds
        if let floor = context.floor {
            input.floor_id_available = floor.id.isEmpty ? 0 : 1
            input.floor_frame_id_available = floor.frameID.isEmpty ? 0 : 1
            input.floor_classification_usable = ["floor", "unclassified"].contains(floor.classification) ? 1 : 0
            input.floor_timestamp_s = floor.timestamp
            input.floor = AFSCPlane(origin: AFSCVec3(x: Double(floor.origin.x), y: Double(floor.origin.y), z: Double(floor.origin.z)),
                                    normal: AFSCVec3(x: Double(floor.normal.x), y: Double(floor.normal.y), z: Double(floor.normal.z)))
        }
        input.world_from_optical = TagDebugMath.coreWorldFromOptical(context.cameraToWorld)
        input.intrinsics = TagDebugMath.coreIntrinsics(context.intrinsics)
        input.pose = TagDebugMath.corePoseObservation(detection)
        input.settings = TagDebugMath.coreMeasurementSettings(context.settings)
        let depth = detection["depth"] as? [String: Any] ?? [:]
        let confidence = (depth["centerConfidence"] as? NSNumber)?.intValue
        input.depth = TagDebugMath.coreDepthObservation(depth: TagDebugMath.number(depth["centerDepthMeters"]),
                                                       confidence: confidence.map(Double.init))
        let center = TagDebugMath.numbers(detection["center"], count: 2)
        input.center_available = center == nil ? 0 : 1
        input.center_px = AFSCVec2(x: center?[0] ?? 0, y: center?[1] ?? 0)
        let evaluation = afsc_floor_height(&input)
        guard evaluation.available != 0, let floor = context.floor else {
            output["reason"] = reason(evaluation.reason)
            return output
        }
        let source = evaluation.source == AFSC_HEIGHT_SOURCE_DEPTH ? "sceneDepth" : "tagPose"
        let acceptedSceneOpticalDepthMeters = TagDebugMath.coreValue(evaluation.accepted_depth_z_m)
        let absoluteOpticalDepthDifferenceMeters = TagDebugMath.coreValue(evaluation.depth_difference_m)
        let opticalPointMeters = [evaluation.optical_m.x, evaluation.optical_m.y, evaluation.optical_m.z]
        // Preserve the native Float world-coordinate representation in recording payloads.
        let world = SIMD3<Float>(Float(evaluation.world_m.x), Float(evaluation.world_m.y), Float(evaluation.world_m.z))
        let foot = SIMD3<Float>(Float(evaluation.floor_foot_world_m.x), Float(evaluation.floor_foot_world_m.y), Float(evaluation.floor_foot_world_m.z))
        guard SpatialMeasurementMath.finite(world), SpatialMeasurementMath.finite(foot) else {
            output["reason"] = "invalidGeometry"; return output
        }
        let verticalHeightMeters = evaluation.height_m
        let basis: [String: Any] = ["id": floor.id, "originWorldMeters": SpatialMeasurementMath.array(floor.origin),
            "normalWorld": SpatialMeasurementMath.array(floor.normal), "frameId": floor.frameID, "timestamp": floor.timestamp,
            "segmentId": floor.segmentID, "classification": floor.classification, "operatorConfirmed": true,
            "observedNormalWorld": SpatialMeasurementMath.array(floor.observedNormal), "levelFloorWithGravity": floor.levelFloorWithGravity,
            "tiltSource": floor.tiltSource, "tiltAvailable": floor.observedTiltDegrees != nil,
            "observedTiltDegrees": floor.observedTiltDegrees as Any? ?? NSNull(), "effectiveTiltDegrees": floor.effectiveTiltDegrees as Any? ?? NSNull(),
            "floorFit": floor.floorFit as Any? ?? NSNull()]
        output.merge(["available": true, "meters": verticalHeightMeters, "source": source,
            "reason": source == "sceneDepth" ? "valid" : "poseFallbackMissingDepth", "floor": basis,
            "worldMeters": SpatialMeasurementMath.array(world), "floorFootWorldMeters": SpatialMeasurementMath.array(foot),
            "opticalMeters": opticalPointMeters, "centerPixel": center as Any? ?? NSNull(),
            "centerDepthMeters": acceptedSceneOpticalDepthMeters as Any? ?? NSNull(), "centerConfidence": confidence as Any? ?? NSNull(),
            "poseZMeters": input.pose.translation.z, "depthDifferenceMeters": absoluteOpticalDepthDifferenceMeters as Any? ?? NSNull(),
            "severity": TagDebugMath.coreSeverity(evaluation.severity)]) { _, new in new }
        return output
    }
    private static func reason(_ value: AFSCHeightReason) -> String {
        switch value {
        case AFSC_HEIGHT_FLOOR_NOT_SELECTED: return "floorNotSelected"
        case AFSC_HEIGHT_SEGMENT_MISMATCH: return "segmentMismatch"
        case AFSC_HEIGHT_TRACKING_LIMITED: return "trackingLimited"
        case AFSC_HEIGHT_STALE_FRAME: return "staleFrame"
        case AFSC_HEIGHT_INVALID_FLOOR: return "invalidFloor"
        case AFSC_HEIGHT_INVALID_POSE: return "invalidPose"
        case AFSC_HEIGHT_AMBIGUOUS_POSE: return "ambiguousPose"
        case AFSC_HEIGHT_TOO_FAR: return "tooFar"
        case AFSC_HEIGHT_BAD_ANGLE: return "badAngle"
        case AFSC_HEIGHT_LOW_CONFIDENCE_POSE: return "lowConfidencePose"
        case AFSC_HEIGHT_DEPTH_MISMATCH: return "depthMismatch"
        case AFSC_HEIGHT_INVALID_CENTER: return "invalidCenter"
        case AFSC_HEIGHT_INVALID_GEOMETRY: return "invalidGeometry"
        case AFSC_HEIGHT_INVALID_INTERSECTION: return "invalidFloorIntersection"
        default: return "valid"
        }
    }
}
