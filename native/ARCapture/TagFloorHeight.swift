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
            "method": "gravity-vertical intersection with an operator-confirmed floor", "estimate": true]
        func unavailable(_ reason: String) -> [String: Any] { output["reason"] = reason; return output }
        guard let floor = context.floor else { return output }
        guard floor.segmentID == context.segmentID else { return unavailable("segmentMismatch") }
        guard context.tracking == "normal" else { return unavailable("trackingLimited") }
        guard context.timestamp.isFinite, context.frameAgeSeconds.isFinite, context.frameAgeSeconds >= 0,
              context.frameAgeSeconds <= 0.4, !context.frameID.isEmpty else { return unavailable("staleFrame") }
        guard !floor.id.isEmpty, !floor.frameID.isEmpty, floor.timestamp.isFinite,
              SpatialMeasurementMath.finite(floor.origin), SpatialMeasurementMath.finite(floor.normal),
              ["floor", "unclassified"].contains(floor.classification) else { return unavailable("invalidFloor") }
        let intrinsicValues = (0..<3).flatMap { column in (0..<3).map { row in context.intrinsics[column][row] } }
        let fx = Double(context.intrinsics.columns.0.x), fy = Double(context.intrinsics.columns.1.y)
        let cx = Double(context.intrinsics.columns.2.x), cy = Double(context.intrinsics.columns.2.y)
        guard validCameraTransform(context.cameraToWorld), intrinsicValues.allSatisfy(\.isFinite), fx > 0, fy > 0,
              let pose = detection["pose"] as? [String: Any],
              let translation = TagDebugMath.numbers(pose["translation"], count: 3), translation[2] > 0,
              let range = TagDebugMath.number(pose["rangeMeters"]), range > 0,
              let angle = TagDebugMath.number(pose["planeAngleDegrees"]), angle >= 0,
              let rms = TagDebugMath.number(pose["reprojectionRMSEPixels"]), rms >= 0 else { return unavailable("invalidPose") }
        guard pose["ambiguous"] as? Bool == false else { return unavailable("ambiguousPose") }
        guard range <= context.settings.maxDistanceMeters else { return unavailable("tooFar") }
        guard angle <= context.settings.maxPlaneAngleDegrees else { return unavailable("badAngle") }
        guard rms <= context.settings.maxReprojectionErrorPixels,
              TagDebugMath.number(detection["hamming"]) == 0,
              let margin = TagDebugMath.number(detection["decisionMargin"]), margin > 0 else { return unavailable("lowConfidencePose") }
        let depth = detection["depth"] as? [String: Any] ?? [:]
        let confidence = (depth["centerConfidence"] as? NSNumber)?.intValue
        let acceptedDepth = TagDebugMath.number(depth["centerDepthMeters"]).flatMap {
            $0 > 0 && [1, 2].contains(confidence ?? -1) ? $0 : nil
        }
        let difference = acceptedDepth.map { abs($0-translation[2]) }
        if let difference, difference > context.settings.rejectDepthDifferenceMeters + 1e-9 { return unavailable("depthMismatch") }
        let optical: [Double]
        let source: String
        let center = TagDebugMath.numbers(detection["center"], count: 2)
        if let acceptedDepth {
            guard let center, center[0] >= 0, center[1] >= 0 else { return unavailable("invalidCenter") }
            optical = [(center[0]-cx)/fx*acceptedDepth, (center[1]-cy)/fy*acceptedDepth, acceptedDepth]
            source = "sceneDepth"
        } else {
            optical = translation
            source = "tagPose"
        }
        guard optical.allSatisfy(\.isFinite) else { return unavailable("invalidGeometry") }
        // ARKit camera looks along -Z with +Y up; detector coordinates use +Y down, +Z forward.
        let cameraPoint = SIMD4<Float>(Float(optical[0]), -Float(optical[1]), -Float(optical[2]), 1)
        let transformed = context.cameraToWorld * cameraPoint
        let world = SIMD3<Float>(transformed.x, transformed.y, transformed.z)
        guard SpatialMeasurementMath.finite(world), transformed.w.isFinite, abs(transformed.w-1) < 1e-3 else { return unavailable("invalidGeometry") }
        let foot: SIMD3<Float>
        do { foot = try SpatialMeasurementMath.verticalFoot(of: world, onto: floor) }
        catch { return unavailable("invalidFloorIntersection") }
        let height = Double(world.y-foot.y)
        guard height.isFinite, height >= 0 else { return unavailable("invalidFloorIntersection") }
        let basis: [String: Any] = ["id": floor.id, "originWorldMeters": SpatialMeasurementMath.array(floor.origin),
            "normalWorld": SpatialMeasurementMath.array(floor.normal), "frameId": floor.frameID, "timestamp": floor.timestamp,
            "segmentId": floor.segmentID, "classification": floor.classification, "operatorConfirmed": true]
        output.merge(["available": true, "meters": height, "source": source,
            "reason": source == "sceneDepth" ? "valid" : "poseFallbackMissingDepth", "floor": basis,
            "worldMeters": SpatialMeasurementMath.array(world), "floorFootWorldMeters": SpatialMeasurementMath.array(foot),
            "opticalMeters": optical, "centerPixel": center as Any? ?? NSNull(),
            "centerDepthMeters": acceptedDepth as Any? ?? NSNull(), "centerConfidence": confidence as Any? ?? NSNull(),
            "poseZMeters": translation[2], "depthDifferenceMeters": difference as Any? ?? NSNull(),
            "severity": source == "tagPose" || (difference ?? 0) > context.settings.warningDepthDifferenceMeters + 1e-9 ? "warning" : "good"]) { _, new in new }
        return output
    }
    private static func validCameraTransform(_ matrix: simd_float4x4) -> Bool {
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { matrix[column][$0].isFinite } }),
              abs(matrix.columns.0.w) < 1e-4, abs(matrix.columns.1.w) < 1e-4,
              abs(matrix.columns.2.w) < 1e-4, abs(matrix.columns.3.w-1) < 1e-4 else { return false }
        let rotation = simd_float3x3(columns: (
            SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)))
        guard abs(simd_determinant(rotation)-1) < 1e-3 else { return false }
        for a in 0..<3 { for b in 0..<3 {
            if abs(simd_dot(rotation[a], rotation[b]) - (a == b ? 1 : 0)) >= 1e-3 { return false }
        } }
        return true
    }
}
