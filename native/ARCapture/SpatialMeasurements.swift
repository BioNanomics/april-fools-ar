import Foundation
import simd

enum SpatialMode: String { case distance, height, selectFloor, tagWidth }

struct SpatialPoint {
    let world: SIMD3<Float>
    let record: [String: Any]
}

struct SpatialPlane {
    let id: String
    let classification: String
    let origin: SIMD3<Float>
    let normal: SIMD3<Float>
    let vertices: [SIMD3<Float>]
    let segmentID: String
    let frameID: String
    let timestamp: Double
    var dictionary: [String: Any] {
        ["id": id, "classification": classification, "originWorldMeters": SpatialMeasurementMath.array(origin),
         "normalWorld": SpatialMeasurementMath.array(normal), "boundaryWorldMeters": vertices.map(SpatialMeasurementMath.array),
         "segmentId": segmentID, "frameId": frameID, "timestamp": timestamp,
         "source": "ARPlaneAnchor", "operatorConfirmed": false]
    }
}

struct SpatialMeasurement {
    let id: String
    let kind: String
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let segmentID: String
    let timestamp: Double
    let sourcePoints: [[String: Any]]
    let floor: SpatialPlane?
    var distanceMeters: Double { Double(simd_length(end-start)) }
    var verticalMeters: Double { Double(end.y-start.y) }
    var horizontalMeters: Double { Double(simd_length(SIMD2<Float>(end.x-start.x, end.z-start.z))) }
    var dictionary: [String: Any] {
        var datum = floor?.dictionary
        datum?["operatorConfirmed"] = true
        return ["id": id, "kind": kind, "segmentId": segmentID, "timestamp": timestamp,
            "startWorldMeters": SpatialMeasurementMath.array(start), "endWorldMeters": SpatialMeasurementMath.array(end),
            "distanceMeters": distanceMeters, "verticalMeters": verticalMeters, "horizontalMeters": horizontalMeters,
            "sourcePoints": sourcePoints, "floor": datum as Any? ?? NSNull(),
            "heightMeters": kind == "height" ? verticalMeters as Any : NSNull(),
            "evidence": "AR/LiDAR estimate; absolute accuracy has not been independently validated"]
    }
}

enum SpatialMeasurementMath {
    static func array(_ point: SIMD3<Float>) -> [Double] { [Double(point.x), Double(point.y), Double(point.z)] }
    static func finite(_ point: SIMD3<Float>) -> Bool { point.x.isFinite && point.y.isFinite && point.z.isFinite }
    static func validate(tracking: String, frameAgeSeconds: Double) throws {
        guard tracking == "normal", frameAgeSeconds.isFinite, frameAgeSeconds >= 0, frameAgeSeconds <= 0.5 else {
            throw SpatialError.invalid("Wait for fresh frames and normal tracking before measuring.")
        }
    }
    static func verticalFoot(of target: SIMD3<Float>, onto floor: SpatialPlane) throws -> SIMD3<Float> {
        guard finite(target), finite(floor.origin), finite(floor.normal), simd_length(floor.normal) > 0,
              abs(floor.normal.y) / simd_length(floor.normal) >= 0.8 else {
            throw SpatialError.invalid("The confirmed floor must be a finite, approximately horizontal plane.")
        }
        let height = simd_dot(floor.normal, target-floor.origin) / floor.normal.y
        let foot = target - SIMD3<Float>(0, height, 0)
        guard height.isFinite, height >= 0, height <= 30, finite(foot) else {
            throw SpatialError.invalid("The target must be above the confirmed floor.")
        }
        return foot
    }
    enum SpatialError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }
}

struct SpatialMeasurementState {
    private(set) var segmentID: String
    private(set) var mode = SpatialMode.distance
    private(set) var pending = [SpatialPoint]()
    private(set) var completed = [SpatialMeasurement]()
    private(set) var floor: SpatialPlane?
    let maximumCount: Int
    init(segmentID: String, maximumCount: Int = 50) {
        self.segmentID = segmentID; self.maximumCount = max(1, min(50, maximumCount))
    }
    mutating func setMode(_ requested: SpatialMode) {
        clearPending()
        mode = requested == .height && floor == nil ? .selectFloor : requested
    }
    mutating func confirmFloor(_ plane: SpatialPlane, tracking: String, frameAgeSeconds: Double) throws {
        try SpatialMeasurementMath.validate(tracking: tracking, frameAgeSeconds: frameAgeSeconds)
        guard plane.segmentID == segmentID, !plane.id.isEmpty, !plane.frameID.isEmpty, plane.timestamp.isFinite,
              ["floor", "unclassified"].contains(plane.classification),
              plane.vertices.count >= 3, plane.vertices.allSatisfy(SpatialMeasurementMath.finite) else {
            throw SpatialMeasurementMath.SpatialError.invalid("Select a current floor or unclassified horizontal surface.")
        }
        _ = try SpatialMeasurementMath.verticalFoot(of: plane.origin, onto: plane)
        floor = plane; clearPending(); mode = .height
    }
    mutating func append(_ point: SpatialPoint, tracking: String, frameAgeSeconds: Double) throws -> SpatialMeasurement? {
        try SpatialMeasurementMath.validate(tracking: tracking, frameAgeSeconds: frameAgeSeconds)
        let confidence = (point.record["confidence"] as? NSNumber)?.intValue ?? -1
        let depth = (point.record["depthMeters"] as? NSNumber)?.doubleValue ?? .nan
        guard SpatialMeasurementMath.finite(point.world), point.record["segmentId"] as? String == segmentID, point.record["source"] as? String == "sceneDepth",
              [1, 2].contains(confidence), depth.isFinite, depth > 0,
              let timestamp = (point.record["timestamp"] as? NSNumber)?.doubleValue, timestamp.isFinite,
              let frameID = point.record["frameId"] as? String, !frameID.isEmpty else {
            throw SpatialMeasurementMath.SpatialError.invalid("Select a valid scene-depth point with confidence 1 or 2 in the current segment.")
        }
        guard mode != .selectFloor else { throw SpatialMeasurementMath.SpatialError.invalid("Tap a visible horizontal surface to confirm the floor first.") }
        guard mode == .tagWidth || completed.count < maximumCount else {
            throw SpatialMeasurementMath.SpatialError.invalid("The live measurement limit is reached. Clear measurements before adding another.")
        }
        let measurement: SpatialMeasurement
        if mode == .height {
            guard let floor, floor.segmentID == segmentID else { throw SpatialMeasurementMath.SpatialError.invalid("Confirm a floor before measuring height.") }
            let foot = try SpatialMeasurementMath.verticalFoot(of: point.world, onto: floor)
            let constructed: [String: Any] = ["worldMeters": SpatialMeasurementMath.array(foot), "source": "vertical-intersection-with-confirmed-floor",
                "floorId": floor.id, "segmentId": segmentID, "frameId": frameID, "timestamp": timestamp]
            measurement = SpatialMeasurement(id: UUID().uuidString, kind: "height", start: foot, end: point.world,
                segmentID: segmentID, timestamp: timestamp, sourcePoints: [constructed, point.record], floor: floor)
            pending = []
        } else {
            if pending.count >= 2 { clearPending() }
            pending.append(point)
            guard pending.count == 2, mode != .tagWidth else { return nil }
            measurement = SpatialMeasurement(id: UUID().uuidString, kind: "distance", start: pending[0].world, end: point.world,
                segmentID: segmentID, timestamp: timestamp, sourcePoints: pending.map(\.record), floor: nil)
        }
        completed.append(measurement)
        return measurement
    }
    mutating func clearPending() { pending.removeAll() }
    mutating func clearMeasurements() { clearPending(); completed.removeAll() }
    mutating func reset(segmentID: String) {
        self.segmentID = segmentID; clearMeasurements(); floor = nil
        if mode == .height || mode == .selectFloor { mode = .selectFloor }
    }
}
