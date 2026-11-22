import Foundation
import CoreFoundation
import simd

/// A live derived annotation. It is never appended to persistent manual measurement history.
struct TagHeightVector {
    let tagID: Int
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let heightMeters: Double
    let source: String
    let severity: String
    let frameID: String
    let segmentID: String
    let floorID: String
    let floor: SpatialPlane
    let timestamp: Double
    var midpoint: SIMD3<Float> { start + (end-start)/2 }
    var expiresAt: Double { timestamp + 0.4 }
}

enum TagHeightVectors {
    static func make(from detections: [[String: Any]], floor: SpatialPlane?, segmentID: String, frameID: String?,
                     tracking: String, mode: SpatialMode, now: Double) -> [TagHeightVector] {
        guard tracking == "normal", mode != .selectFloor, mode != .tagWidth, now.isFinite,
              let floor, floor.segmentID == segmentID, !floor.id.isEmpty, !floor.frameID.isEmpty, floor.timestamp.isFinite,
              SpatialMeasurementMath.finite(floor.origin), SpatialMeasurementMath.finite(floor.normal), simd_length(floor.normal) > 0,
              let frameID, !frameID.isEmpty else { return [] }
        return detections.prefix(64).compactMap { detection in
            guard let rawID = number(detection["id"]), rawID >= 0, rawID < Double(Int.max), rawID.rounded() == rawID,
                  let height = detection["floorHeight"] as? [String: Any], flag(height["available"]) == true,
                  height["segmentId"] as? String == segmentID, height["frameId"] as? String == frameID,
                  height["floorId"] as? String == floor.id, let timestamp = number(height["timestamp"]),
                  now-timestamp >= 0, now-timestamp <= 0.4,
                  let meters = number(height["meters"]), meters >= 0, meters <= 30,
                  let source = height["source"] as? String, ["sceneDepth", "tagPose"].contains(source),
                  let start = point(height["floorFootWorldMeters"]), let end = point(height["worldMeters"]),
                  abs(start.x-end.x) <= 1e-4, abs(start.z-end.z) <= 1e-4,
                  abs(Double(end.y-start.y)-meters) <= max(0.001, meters*1e-4), end.y >= start.y,
                  let basis = height["floor"] as? [String: Any], basis["id"] as? String == floor.id,
                  flag(basis["operatorConfirmed"]) == true,
                  basis["segmentId"] as? String == segmentID, basis["frameId"] as? String == floor.frameID,
                  number(basis["timestamp"]) == floor.timestamp,
                  let origin = point(basis["originWorldMeters"]), let normal = point(basis["normalWorld"]),
                  simd_length(origin-floor.origin) <= 1e-5, simd_length(normal-floor.normal) <= 1e-5,
                  abs(simd_dot(floor.normal, start-floor.origin))/simd_length(floor.normal) <= 0.001,
                  flag(basis["levelFloorWithGravity"]) == floor.levelFloorWithGravity else { return nil }
            return TagHeightVector(tagID: Int(rawID), start: start, end: end, heightMeters: meters,
                source: source, severity: height["severity"] as? String ?? "neutral",
                frameID: frameID, segmentID: segmentID, floorID: floor.id, floor: floor, timestamp: timestamp)
        }
    }
    private static func number(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func flag(_ raw: Any?) -> Bool? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    private static func point(_ raw: Any?) -> SIMD3<Float>? {
        guard let values = raw as? [Any], values.count == 3 else { return nil }
        let numbers = values.compactMap(number)
        guard numbers.count == 3 else { return nil }
        let result = SIMD3<Float>(Float(numbers[0]), Float(numbers[1]), Float(numbers[2]))
        return SpatialMeasurementMath.finite(result) ? result : nil
    }
}
