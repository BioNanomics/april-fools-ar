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
    let observedNormal: SIMD3<Float>
    let levelFloorWithGravity: Bool
    let tiltSource: String
    let floorFit: [String: Any]?
    init(id: String, classification: String, origin: SIMD3<Float>, normal: SIMD3<Float>, vertices: [SIMD3<Float>],
         segmentID: String, frameID: String, timestamp: Double, observedNormal: SIMD3<Float>? = nil,
         levelFloorWithGravity: Bool = false, tiltSource: String = "unavailable", floorFit: [String: Any]? = nil) {
        self.id = id; self.classification = classification; self.origin = origin; self.normal = normal; self.vertices = vertices
        self.segmentID = segmentID; self.frameID = frameID; self.timestamp = timestamp
        self.observedNormal = observedNormal ?? normal; self.levelFloorWithGravity = levelFloorWithGravity
        self.tiltSource = tiltSource; self.floorFit = floorFit
    }
    var observedTiltDegrees: Double? { tiltSource == "sceneDepth-plane-fit" ? SpatialMeasurementMath.floorTiltDegrees(observedNormal) : nil }
    var effectiveTiltDegrees: Double? { levelFloorWithGravity ? 0 : observedTiltDegrees }
    var dictionary: [String: Any] {
        ["id": id, "classification": classification, "originWorldMeters": SpatialMeasurementMath.array(origin),
         "normalWorld": SpatialMeasurementMath.array(normal), "boundaryWorldMeters": vertices.map(SpatialMeasurementMath.array),
         "segmentId": segmentID, "frameId": frameID, "timestamp": timestamp,
         "source": tiltSource == "sceneDepth-plane-fit" ? "ARPlaneAnchor+sceneDepth-plane-fit" : "ARPlaneAnchor", "operatorConfirmed": false,
         "observedNormalWorld": SpatialMeasurementMath.array(observedNormal), "levelFloorWithGravity": levelFloorWithGravity,
         "tiltSource": tiltSource, "tiltAvailable": observedTiltDegrees != nil,
         "observedTiltDegrees": observedTiltDegrees as Any? ?? NSNull(), "effectiveTiltDegrees": effectiveTiltDegrees as Any? ?? NSNull(),
         "floorFit": floorFit as Any? ?? NSNull()]
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
    var distanceMeters: Double { SpatialMeasurementMath.distance(from: start, to: end).distance_meters }
    var verticalMeters: Double { SpatialMeasurementMath.distance(from: start, to: end).vertical_meters }
    var horizontalMeters: Double { SpatialMeasurementMath.distance(from: start, to: end).horizontal_meters }
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

struct SpatialDistanceTriangle {
    let corner: SIMD3<Float>
    let distanceMeters: Double
    let horizontalMeters: Double
    let verticalMeters: Double
}

enum SpatialMeasurementMath {
    static func array(_ point: SIMD3<Float>) -> [Double] { [Double(point.x), Double(point.y), Double(point.z)] }
    static func finite(_ point: SIMD3<Float>) -> Bool { point.x.isFinite && point.y.isFinite && point.z.isFinite }
    static func coreVector(_ point: SIMD3<Float>) -> AFSCVec3 {
        AFSCVec3(x: Double(point.x), y: Double(point.y), z: Double(point.z))
    }
    static func swiftVector(_ point: AFSCVec3) -> SIMD3<Float> {
        SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z))
    }
    static func corePlane(_ plane: SpatialPlane) -> AFSCPlane {
        AFSCPlane(origin: coreVector(plane.origin), normal: coreVector(plane.normal))
    }
    static func distance(from start: SIMD3<Float>, to end: SIMD3<Float>) -> AFSCDistance {
        var result = AFSCDistance()
        guard afsc_distance(coreVector(start), coreVector(end), &result) == AFSC_GEOMETRY_OK else {
            return AFSCDistance(distance_meters: .nan, vertical_meters: .nan, horizontal_meters: .nan)
        }
        return result
    }
    static func distanceTriangle(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SpatialDistanceTriangle? {
        var result = AFSCDistanceTriangle()
        guard afsc_distance_triangle(coreVector(start), coreVector(end), &result) == AFSC_GEOMETRY_OK else { return nil }
        let corner = swiftVector(result.corner)
        guard finite(corner) else { return nil }
        return SpatialDistanceTriangle(corner: corner, distanceMeters: result.lengths.distance_meters,
            horizontalMeters: result.lengths.horizontal_meters, verticalMeters: result.lengths.vertical_meters)
    }
    static func floorTiltDegrees(_ normal: SIMD3<Float>) -> Double? {
        var radians = 0.0
        guard afsc_floor_tilt(coreVector(normal), &radians) == AFSC_GEOMETRY_OK else { return nil }
        return radians * 180 / .pi
    }
    static func effectiveFloor(_ observed: SpatialPlane, levelWithGravity: Bool) -> SpatialPlane {
        guard levelWithGravity else { return observed }
        return SpatialPlane(id: observed.id, classification: observed.classification, origin: observed.origin,
            normal: SIMD3<Float>(0, 1, 0), vertices: observed.vertices.map { SIMD3<Float>($0.x, observed.origin.y, $0.z) },
            segmentID: observed.segmentID, frameID: observed.frameID, timestamp: observed.timestamp,
            observedNormal: observed.observedNormal, levelFloorWithGravity: true, tiltSource: observed.tiltSource, floorFit: observed.floorFit)
    }
    /// Horizontal coverage, with a rotation-invariant minimum width to reject long narrow strips.
    static func floorCoverage(_ plane: SpatialPlane) -> (areaSquareMeters: Double, minSpanMeters: Double) {
        let vertices = plane.vertices.map(coreVector)
        var coverage = AFSCFloorCoverage()
        let status = vertices.withUnsafeBufferPointer {
            afsc_floor_coverage($0.baseAddress, $0.count, &coverage)
        }
        guard status == AFSC_GEOMETRY_OK else { return (0, 0) }
        return (coverage.area_square_meters, coverage.min_span_meters)
    }
    static func validate(tracking: String, frameAgeSeconds: Double) throws {
        guard tracking == "normal", frameAgeSeconds.isFinite, frameAgeSeconds >= 0, frameAgeSeconds <= 0.5 else {
            throw SpatialError.invalid("Wait for fresh frames and normal tracking before measuring.")
        }
    }
    static func verticalFoot(of target: SIMD3<Float>, onto floor: SpatialPlane) throws -> SIMD3<Float> {
        var result = AFSCVec3()
        let status = afsc_vertical_foot(coreVector(target), corePlane(floor), &result)
        if status == AFSC_GEOMETRY_INVALID_PLANE || status == AFSC_GEOMETRY_INVALID_ARGUMENT {
            throw SpatialError.invalid("The confirmed floor must be a finite, approximately horizontal plane.")
        }
        let foot = swiftVector(result)
        guard status == AFSC_GEOMETRY_OK, finite(foot) else {
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
    private(set) var mode = SpatialMode.selectFloor
    private(set) var requestedMode = SpatialMode.distance
    private(set) var candidate: SpatialPlane?
    private(set) var candidateSelectionSource = "none"
    private var currentCandidates = [String: SpatialPlane]()
    private var manualCandidateID: String?
    private(set) var pending = [SpatialPoint]()
    private(set) var completed = [SpatialMeasurement]()
    private(set) var observedFloor: SpatialPlane?
    private(set) var levelFloorWithGravity: Bool
    var floor: SpatialPlane? { observedFloor.map { SpatialMeasurementMath.effectiveFloor($0, levelWithGravity: levelFloorWithGravity) } }
    let maximumCount: Int
    init(segmentID: String, maximumCount: Int = 50, levelFloorWithGravity: Bool = false) {
        self.segmentID = segmentID; self.maximumCount = max(1, min(50, maximumCount))
        self.levelFloorWithGravity = levelFloorWithGravity
    }
    mutating func setFloorLeveling(_ enabled: Bool) {
        guard enabled != levelFloorWithGravity else { return }
        levelFloorWithGravity = enabled; clearPending()
    }
    mutating func setMode(_ requested: SpatialMode) {
        clearPending()
        if requested == .selectFloor {
            if mode != .selectFloor { requestedMode = mode }
            mode = .selectFloor; candidate = nil; manualCandidateID = nil; candidateSelectionSource = "none"
            updateCandidates(Array(currentCandidates.values))
        } else {
            requestedMode = requested
            mode = floor == nil || mode == .selectFloor ? .selectFloor : requested
        }
    }
    mutating func updateCandidates(_ planes: [SpatialPlane]) {
        currentCandidates = [:]
        for plane in planes where validCandidate(plane) { currentCandidates[plane.id] = plane }
        guard mode == .selectFloor else { return }
        if let manualCandidateID {
            candidate = currentCandidates[manualCandidateID]; candidateSelectionSource = "manual"
        } else if let id = candidate?.id, let latest = currentCandidates[id], latest.classification == "floor" {
            candidate = latest; candidateSelectionSource = "automatic"
        } else {
            candidate = currentCandidates.values.filter { $0.classification == "floor" }.max {
                SpatialMeasurementMath.floorCoverage($0).areaSquareMeters < SpatialMeasurementMath.floorCoverage($1).areaSquareMeters
            }
            candidateSelectionSource = candidate == nil ? "none" : "automatic"
        }
    }
    mutating func selectFloorCandidate(_ plane: SpatialPlane, tracking: String, frameAgeSeconds: Double) throws {
        try SpatialMeasurementMath.validate(tracking: tracking, frameAgeSeconds: frameAgeSeconds)
        guard mode == .selectFloor, let latest = currentCandidates[plane.id], validCandidate(latest) else {
            throw SpatialMeasurementMath.SpatialError.invalid("Select a current floor or unclassified horizontal surface.")
        }
        candidate = latest; manualCandidateID = latest.id; candidateSelectionSource = "manual"
    }
    func floorSetupStatus(tracking: String, frameAgeSeconds: Double) -> [String: Any] {
        let coverage = candidate.map(SpatialMeasurementMath.floorCoverage) ?? (areaSquareMeters: 0, minSpanMeters: 0)
        let reason: String
        if candidate == nil { reason = "floorNotSelected" }
        else if tracking != "normal" { reason = "trackingLimited" }
        else if !frameAgeSeconds.isFinite || frameAgeSeconds < 0 || frameAgeSeconds > 0.5 { reason = "staleFrame" }
        else if coverage.areaSquareMeters + 1e-6 < 1 { reason = "insufficientArea" }
        else if coverage.minSpanMeters + 1e-6 < 0.5 { reason = "insufficientSpan" }
        else { reason = "ready" }
        return ["active": mode == .selectFloor, "candidateSelected": candidate != nil, "candidateId": candidate?.id as Any? ?? NSNull(),
            "areaSquareMeters": coverage.areaSquareMeters, "minSpanMeters": coverage.minSpanMeters,
            "ready": mode == .selectFloor && reason == "ready", "reason": reason,
            "selectionSource": candidateSelectionSource, "requestedMode": requestedMode.rawValue]
    }
    mutating func completeFloorSetup(expectedCandidateID: String, tracking: String, frameAgeSeconds: Double) throws {
        try SpatialMeasurementMath.validate(tracking: tracking, frameAgeSeconds: frameAgeSeconds)
        guard mode == .selectFloor, let selected = candidate, selected.id == expectedCandidateID,
              let latest = currentCandidates[selected.id], validCandidate(latest) else {
            throw SpatialMeasurementMath.SpatialError.invalid("The selected floor changed or is no longer current. Review it before tapping Done.")
        }
        let status = floorSetupStatus(tracking: tracking, frameAgeSeconds: frameAgeSeconds)
        guard status["ready"] as? Bool == true else {
            throw SpatialMeasurementMath.SpatialError.invalid("Scan a larger floor patch (at least 1.0 m² and 0.5 m wide), then tap Done.")
        }
        observedFloor = latest; candidate = nil; manualCandidateID = nil; candidateSelectionSource = "none"
        clearPending(); mode = requestedMode
    }
    private func validCandidate(_ plane: SpatialPlane) -> Bool {
        guard plane.segmentID == segmentID, !plane.id.isEmpty, !plane.frameID.isEmpty, plane.timestamp.isFinite,
              ["floor", "unclassified"].contains(plane.classification), plane.vertices.count >= 3,
              plane.vertices.allSatisfy(SpatialMeasurementMath.finite) else { return false }
        return (try? SpatialMeasurementMath.verticalFoot(of: plane.origin, onto: plane)) != nil
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
        guard mode != .selectFloor, let confirmed = floor, confirmed.segmentID == segmentID else {
            throw SpatialMeasurementMath.SpatialError.invalid("Scan and confirm a floor with Done before measuring.")
        }
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
        self.segmentID = segmentID; clearMeasurements(); observedFloor = nil
        mode = .selectFloor; candidate = nil; manualCandidateID = nil; currentCandidates = [:]; candidateSelectionSource = "none"
    }
}
