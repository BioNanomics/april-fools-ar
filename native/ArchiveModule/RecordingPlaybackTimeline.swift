import Foundation
import CoreGraphics
import CoreFoundation
import CryptoKit
import Darwin
import simd

/// Geometry is expressed in unrotated sensor pixels. The player alone applies
/// the movie track's orientation and aspect-fit rectangle.
struct RecordingPlaybackSnapshot {
    struct Tag { let id: String; let label: String; let corners: [CGPoint]; let severity: String }
    struct Line {
        let id: String; let points: [CGPoint]; let label: String?; let style: String
        var accessibilityLabel: String? = nil
    }
    struct Polygon { let id: String; let points: [CGPoint]; let label: String?; let style: String }
    let imageSize: CGSize
    let frameID: String
    let segmentID: String
    let tags: [Tag]
    let lines: [Line]
    let polygons: [Polygon]
    let message: String?
    var recordedPreviewMode: String? = nil
    var rasterSample: RecordingPlaybackRasterSample? = nil
}

/// Immutable, seekable interpretation of the captured observations. Playback
/// does not rerun the detector or alter a recorded measurement's floor datum.
final class RecordingPlaybackTimeline {
    enum TimelineError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let reason): return "Recorded overlays are unavailable: \(reason)" }
        }
    }
    private struct Geometry {
        let transform: simd_float4x4
        let intrinsics: simd_float3x3
        let imageSize: CGSize
        var projection: SpatialProjection.Camera? {
            SpatialProjection.Camera(cameraToWorld: transform, intrinsics: intrinsics, imageSize: imageSize,
                                     displayTransform: .identity, viewportSize: imageSize)
        }
    }
    private struct Frame {
        let time: Double, timestamp: Double, id: String, segment: String, size: CGSize
        let tracking: String
        let previewMode: String?
        let geometry: Geometry?
        let ordinal: Int
    }
    private struct Event {
        let time: Double, ordinal: Int
        let row: [String: Any]
    }
    private struct ExpectedFieldTag {
        let id: Int
        let size: Double
        let fieldFromTag: simd_float4x4
    }
    private struct FieldRegistration {
        let worldFromField: simd_float4x4
        let segment: String
        let time: Double
    }
    private struct State {
        var segment = ""
        var floor: [String: Any]?
        var measurements = [[String: Any]]()
        var pending = [SIMD3<Float>]()
        var settings = [String: Any]()
        var tracking: String?
        var trackingTime = -Double.infinity
        var detectionBoundary = -Double.infinity
        var fieldPackageID: String?
        var fieldPackageHash: String?
        var fieldRegistration: FieldRegistration?
        var fieldMessage: String?
    }
    private let origin: Double
    private let frames: [Frame]
    private let mutations: [Event]
    private let checkpoints: [State]
    private let detections: [String: [Event]]
    private let expectedFieldTags: [ExpectedFieldTag]
    private let fieldFrameBoundaries: [Double]
    let rasterIndex: RecordingPlaybackRasterIndex
    var hasDepthSamples: Bool { rasterIndex.samples.contains { $0.depthFile != nil } }
    var hasConfidenceSamples: Bool { rasterIndex.samples.contains { $0.confidenceFile != nil } }
    private static let stride = 64
    private static let metadataLimit = 16 * 1024 * 1024
    private static let recordLimit = 100_000

    static func load(folderURL: URL) throws -> Self {
        guard folderURL.isFileURL else { throw TimelineError.invalid("expected a local capture folder") }
        let descriptor = Darwin.open(folderURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw TimelineError.invalid("the capture folder cannot be opened") }
        defer { Darwin.close(descriptor) }
        let manifestData = try readMetadata("manifest.json", directory: descriptor)
        let manifest = try object(manifestData, label: "manifest")
        guard flag(manifest["finalized"]) == true else { throw TimelineError.invalid("the capture is not finalized") }
        let frameData = try readMetadata("frames.jsonl", directory: descriptor)
        let eventData = try readMetadata("events.jsonl", directory: descriptor)
        guard let inventory = manifest["fileInventory"] as? [[String: Any]] else {
            throw TimelineError.invalid("the capture has no file integrity inventory")
        }
        for (name, data) in [("frames.jsonl", frameData), ("events.jsonl", eventData)] {
            let matches = inventory.filter { $0["path"] as? String == name }
            guard matches.count == 1, let expected = matches.first,
                  number(expected["bytes"]) == Double(data.count), let sha = expected["sha256"] as? String,
                  sha == hash(data) else { throw TimelineError.invalid("\(name) does not match the saved capture") }
        }
        if let field = manifest["fieldDefinition"], !(field is NSNull) {
            guard let fieldDescriptor = field as? [String: Any], let expectedHash = fieldDescriptor["packageSha256"] as? String else {
                throw TimelineError.invalid("invalid field-definition integrity metadata")
            }
            let name = "field-definition.yaml", data = try readMetadata(name, directory: descriptor)
            let matches = inventory.filter { $0["path"] as? String == name }
            guard matches.count == 1, let entry = matches.first,
                  number(entry["bytes"]) == Double(data.count), entry["sha256"] as? String == hash(data),
                  expectedHash == hash(data) else {
                throw TimelineError.invalid("field-definition.yaml does not match the saved field package")
            }
        }
        return try Self.init(manifest: manifest, frames: records(frameData), events: records(eventData), folderURL: folderURL)
    }

    init(manifest: [String: Any], frames: [[String: Any]], events: [[String: Any]], folderURL: URL? = nil) throws {
        guard Self.flag(manifest["finalized"]) == true, let origin = Self.number(manifest["firstARFrameTimestamp"]),
              frames.count <= Self.recordLimit, events.count <= Self.recordLimit else {
            throw TimelineError.invalid("missing finalized capture clock or too many records")
        }
        self.origin = origin
        self.expectedFieldTags = try Self.fieldTags(manifest)
        self.rasterIndex = RecordingPlaybackRasterIndex(manifest: manifest, frames: frames, events: events,
                                                       origin: origin, folderURL: folderURL)
        let accepted: [Frame] = frames.enumerated().compactMap { ordinal, row in
            guard Self.flag(row["videoAppended"]) == true,
                  let time = Self.number(row["videoPTSSeconds"]), time >= 0,
                  let timestamp = Self.number(row["timestamp"]),
                  let id = Self.identifier(row["frameId"]), let segment = Self.identifier(row["segmentId"]),
                  let size = Self.imageSize(row) else { return nil }
            return Frame(time: time, timestamp: timestamp, id: id, segment: segment, size: size,
                         tracking: row["tracking"] as? String ?? "unavailable", previewMode: Self.previewMode(row["previewMode"]),
                         geometry: Self.geometry(row), ordinal: ordinal)
        }.sorted { $0.time == $1.time ? $0.ordinal < $1.ordinal : $0.time < $1.time }
        guard !accepted.isEmpty else { throw TimelineError.invalid("no indexed video frames") }
        self.frames = accepted
        var boundary = -Double.infinity
        self.fieldFrameBoundaries = accepted.map { frame in
            if frame.tracking != "normal" { boundary = frame.time }
            return boundary
        }
        var mutations = [Event](), groups = [String: [Event]](), previousTime = -Double.infinity
        let names: Set<String> = ["segment", "measurementsAtStart", "floorConfirmed", "floorReferenceChanged",
            "measurementCompleted", "measurementPoint", "measurementsCleared", "measurementsInvalidated",
            "trackingChanged", "debugSettingsAtStart", "settingsChanged", "fieldWalkStarted",
            "fieldRegistrationChanged", "fieldRegistrationInvalidated", "fieldAnchorWarning"]
        for (ordinal, row) in events.enumerated() {
            guard let type = row["type"] as? String, let timestamp = Self.number(row["timestamp"]) else { continue }
            let time = timestamp - origin
            if type == "aprilTagDetections", let segment = Self.identifier(row["segmentId"]) {
                groups[segment, default: []].append(Event(time: time, ordinal: ordinal, row: row))
            } else if names.contains(type) {
                // State changes follow capture queue order. Unlike detections,
                // a late timestamp cannot rewind the history of prior changes.
                previousTime = max(previousTime, time)
                mutations.append(Event(time: previousTime, ordinal: ordinal, row: row))
            }
        }
        for key in groups.keys {
            groups[key]?.sort { $0.time == $1.time ? $0.ordinal < $1.ordinal : $0.time < $1.time }
        }
        self.mutations = mutations
        self.detections = groups
        var state = State()
        state.segment = accepted[0].segment
        if let field = manifest["fieldDefinition"] as? [String: Any] {
            state.fieldPackageID = Self.identifier(field["id"])
            state.fieldPackageHash = field["packageSha256"] as? String
        }
        state.settings = (manifest["aprilTagConfiguration"] as? [String: Any])?["debugSettingsAtStart"] as? [String: Any] ?? [:]
        var checkpoints = [state]
        for (index, event) in mutations.enumerated() {
            Self.apply(event, to: &state)
            if (index + 1) % Self.stride == 0 { checkpoints.append(state) }
        }
        self.checkpoints = checkpoints
    }

    func snapshot(at seconds: Double) -> RecordingPlaybackSnapshot? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let frameCount = Self.upperBound(frames.count) { frames[$0].time <= seconds }
        guard frameCount > 0 else { return nil }
        let frame = frames[frameCount - 1]
        let count = Self.upperBound(mutations.count) { mutations[$0].time <= seconds }
        let checkpoint = count / Self.stride
        var state = checkpoints[checkpoint]
        for index in (checkpoint * Self.stride)..<count { Self.apply(mutations[index], to: &state) }
        var tags = [RecordingPlaybackSnapshot.Tag](), lines = [RecordingPlaybackSnapshot.Line](), polygons = [RecordingPlaybackSnapshot.Polygon]()
        let sameSegment = state.segment == frame.segment
        // A recovery event on an omitted camera frame cannot make the still
        // displayed limited-tracking video frame a valid projection camera.
        let tracking = frame.tracking == "normal" && state.trackingTime >= frame.time
            ? state.tracking ?? frame.tracking : frame.tracking
        let projection = frame.geometry?.projection
        let worldVisible = sameSegment && tracking == "normal" && projection != nil
        let imperial = Self.flag(state.settings["showImperialHeight"]) ?? true
        if worldVisible, let camera = projection {
            if let registration = state.fieldRegistration, registration.segment == frame.segment,
               registration.time > fieldFrameBoundaries[frameCount - 1] + 1e-7 {
                for tag in expectedFieldTags {
                    let worldFromTag = registration.worldFromField * tag.fieldFromTag
                    let half = Float(tag.size / 2)
                    let corners: [SIMD4<Float>] = [SIMD4(-half, half, 0, 1), SIMD4(half, half, 0, 1),
                                                    SIMD4(half, -half, 0, 1), SIMD4(-half, -half, 0, 1)]
                    let world = corners.map { local -> SIMD3<Float> in
                        let point = worldFromTag * local
                        return SIMD3(point.x, point.y, point.z)
                    }
                    guard world.allSatisfy(Self.finite) else { continue }
                    let projected = camera.polygon(world)
                    if projected.count >= 3 {
                        polygons.append(.init(id: "field.expected.\(tag.id)", points: projected,
                                              label: "Expected #\(tag.id)", style: "fieldExpected"))
                    }
                }
            }
            if let floor = state.floor, Self.identifier(floor["segmentId"]) == frame.segment,
               let boundary = Self.points(floor["boundaryWorldMeters"]), boundary.count >= 3 {
                let projected = camera.polygon(boundary)
                if projected.count >= 3 {
                    let tilt = Self.number(floor["effectiveTiltDegrees"])
                    let style = tilt.map { $0 <= 0.5 ? "floor" : "floorTilted" } ?? "floorUnknown"
                    polygons.append(.init(id: "floor", points: projected, label: "Recorded floor", style: style))
                }
            }
            for record in state.measurements.suffix(50) {
                guard Self.identifier(record["segmentId"]) == frame.segment,
                      let id = Self.identifier(record["id"]), let start = Self.point(record["startWorldMeters"]),
                      let end = Self.point(record["endWorldMeters"]) else { continue }
                let height = record["kind"] as? String == "height"
                if height {
                    guard let projected = camera.segment(from: start, to: end) else { continue }
                    let vertical = Self.number(record["verticalMeters"]) ?? Double(end.y-start.y)
                    lines.append(.init(id: "measurement.\(id)", points: projected,
                        label: "Height \(Self.height(abs(vertical), imperial: imperial))", style: "height"))
                    if let floor = record["floor"] as? [String: Any] {
                        Self.addBase(at: start, floor: floor, camera: camera, id: "measurement.\(id).base", to: &polygons)
                    }
                } else if record["kind"] as? String == "distance",
                          let triangle = SpatialMeasurementMath.distanceTriangle(from: start, to: end) {
                    let hasLegs = triangle.horizontalMeters > 1e-6 && abs(triangle.verticalMeters) > 1e-6
                    let summary = String(format: "D %.3f m · H %.3f m · V %+.3f m",
                        triangle.distanceMeters, triangle.horizontalMeters, triangle.verticalMeters)
                    if let projected = camera.segment(from: start, to: end) {
                        lines.append(.init(id: "measurement.\(id)", points: projected,
                            label: hasLegs ? String(format: "D %.3f m", triangle.distanceMeters) : summary, style: "distance",
                            accessibilityLabel: String(format: "Distance %.3f meters. Horizontal %.3f meters. Vertical difference %+.3f meters.",
                                triangle.distanceMeters, triangle.horizontalMeters, triangle.verticalMeters)))
                    }
                    if hasLegs {
                        if let horizontal = camera.segment(from: start, to: triangle.corner) {
                            lines.append(.init(id: "measurement.\(id).horizontal", points: horizontal,
                                label: String(format: "H %.3f m", triangle.horizontalMeters), style: "distance-horizontal"))
                        }
                        if let vertical = camera.segment(from: triangle.corner, to: end) {
                            lines.append(.init(id: "measurement.\(id).vertical", points: vertical,
                                label: String(format: "V %+.3f m", triangle.verticalMeters), style: "distance-vertical"))
                        }
                    }
                } else if let projected = camera.segment(from: start, to: end) {
                    let distance = Self.number(record["distanceMeters"]) ?? Double(simd_length(end-start))
                    let vertical = Self.number(record["verticalMeters"]) ?? Double(end.y-start.y)
                    lines.append(.init(id: "measurement.\(id)", points: projected,
                        label: String(format: "%.3f m · ΔY %.3f m", distance, vertical), style: "distance"))
                }
            }
            for (index, point) in state.pending.prefix(1).enumerated() {
                if let pixel = camera.point(point) {
                    lines.append(.init(id: "pending.\(index).h", points: [CGPoint(x: pixel.x-6, y: pixel.y), CGPoint(x: pixel.x+6, y: pixel.y)], label: "Point 1", style: "pending"))
                    lines.append(.init(id: "pending.\(index).v", points: [CGPoint(x: pixel.x, y: pixel.y-6), CGPoint(x: pixel.x, y: pixel.y+6)], label: nil, style: "pending"))
                }
            }
        }
        if sameSegment, let candidates = detections[frame.segment] {
            let latest = Self.upperBound(candidates.count) { candidates[$0].time <= frame.timestamp - origin + 1e-7 }
            if latest > 0 {
                let event = candidates[latest - 1]
                let age = seconds - event.time
                if age >= -1e-7, age <= 0.4, event.time > state.detectionBoundary + 1e-7,
                   Self.flag(event.row["analysisSucceeded"]) == true,
                   let rows = event.row["detections"] as? [[String: Any]] {
                    let settings = event.row["debugSettings"] as? [String: Any] ?? state.settings
                    let source = Self.geometry(event.row)
                    let exact = Self.identifier(event.row["frameId"]) == frame.id
                    for (index, detection) in rows.prefix(64).enumerated() {
                        guard let tagID = Self.number(detection["id"]), tagID >= 0, tagID.rounded() == tagID, tagID < Double(Int.max) else { continue }
                        let identifier = "tag.\(Int(tagID)).\(index)"
                        let debug = detection["debug"] as? [String: Any] ?? [:]
                        let severity = debug["severity"] as? String ?? "neutral"
                        let pose = Self.usablePose(detection)
                        let corners = Self.imagePoints(detection["corners"])
                        var projectedCorners: [CGPoint]?
                        if exact, corners?.count == 4 { projectedCorners = corners }
                        else if worldVisible, let source, let pose, let camera = projection, let corners, corners.count == 4 {
                            let world = corners.compactMap { Self.intersect($0, pose: pose, source: source) }
                            if world.count == 4 {
                                let projected = world.compactMap(camera.point)
                                if projected.count == 4 { projectedCorners = projected }
                            }
                        }
                        if let projectedCorners {
                            tags.append(.init(id: identifier, label: Self.tagLabel(Int(tagID), detection: detection, event: event.row, settings: settings), corners: projectedCorners, severity: severity))
                        }
                        if worldVisible, let camera = projection {
                            Self.addTagHeight(detection, event: event.row, activeFloor: state.floor, segment: frame.segment,
                                              camera: camera, id: identifier, imperial: Self.flag(settings["showImperialHeight"]) ?? true,
                                              lines: &lines, polygons: &polygons)
                            if Self.flag(settings["showPoseAxes"]) == true, let source, let pose {
                                let width = Self.number(pose["tagSizeMeters"]) ?? Self.number(settings["tagSizeMeters"]) ?? 0.1651
                                if width > 0, width <= 2 { Self.addAxes(pose, source: source, camera: camera, length: Float(width/2), id: identifier, lines: &lines) }
                            }
                        }
                    }
                }
            }
        }
        let message: String?
        if !sameSegment { message = "Recorded tracking changed; spatial overlays are hidden." }
        else if tracking != "normal" { message = "Recorded tracking is limited; spatial overlays are hidden." }
        else if projection == nil { message = "Recorded camera geometry is unavailable." }
        else { message = state.fieldMessage }
        return RecordingPlaybackSnapshot(imageSize: frame.size, frameID: frame.id, segmentID: frame.segment,
                                         tags: tags, lines: lines, polygons: polygons, message: message,
                                         recordedPreviewMode: frame.previewMode,
                                         rasterSample: sameSegment ? rasterIndex.sample(at: seconds, segment: frame.segment,
                                                                                      imageSize: frame.size) : nil)
    }

    private static func apply(_ event: Event, to state: inout State) {
        let row = event.row, type = row["type"] as? String ?? ""
        let segment = identifier(row["segmentId"])
        if type == "segment" {
            if let segment, segment != state.segment {
                state.segment = segment; state.floor = nil; state.measurements = []; state.pending = []
                state.tracking = nil; state.trackingTime = -.infinity
                state.fieldRegistration = nil; state.fieldMessage = nil
                state.detectionBoundary = max(state.detectionBoundary, event.time)
            }
            return
        }
        if type == "measurementsInvalidated" {
            state.floor = nil; state.measurements = []; state.pending = []
            state.fieldRegistration = nil
            state.detectionBoundary = max(state.detectionBoundary, event.time)
            if let next = identifier(row["newSegmentId"]) { state.segment = next }
            return
        }
        if type == "debugSettingsAtStart" || type == "settingsChanged" {
            if let settings = row["settings"] as? [String: Any] { state.settings = settings }
            if type == "settingsChanged" {
                state.pending = []; state.detectionBoundary = max(state.detectionBoundary, event.time)
                state.fieldRegistration = nil
            }
            return
        }
        if let segment, segment != state.segment { return }
        switch type {
        case "fieldWalkStarted", "fieldRegistrationChanged", "fieldRegistrationInvalidated", "fieldAnchorWarning":
            guard state.fieldPackageID != nil else { return }
            guard identifier(row["packageId"]) == state.fieldPackageID,
                  identifier(row["packageSha256"]) == state.fieldPackageHash else {
                state.fieldRegistration = nil
                state.fieldMessage = "Recorded field identity changed; expected placements are hidden."
                return
            }
            let field = row["field"] as? [String: Any] ?? [:]
            state.fieldMessage = field["reason"] as? String ?? row["reason"] as? String
            if type == "fieldAnchorWarning" { return } // Warnings never rekey field geometry.
            if type == "fieldRegistrationInvalidated" {
                state.fieldRegistration = nil
                return
            }
            guard let alignment = field["alignment"] as? String,
                  ["provisional", "checked", "degraded", "unverified"].contains(alignment),
                  let sourceSegment = identifier(field["segmentId"]), sourceSegment == state.segment,
                  let transform = rigidMatrix(field["worldFromFieldColumnMajor"]) else {
                state.fieldRegistration = nil
                return
            }
            state.fieldRegistration = FieldRegistration(worldFromField: transform, segment: sourceSegment, time: event.time)
        case "measurementsAtStart":
            state.floor = row["floor"] as? [String: Any]
            state.measurements = Array((row["measurements"] as? [[String: Any]] ?? []).suffix(50)); state.pending = []
        case "floorConfirmed", "floorReferenceChanged":
            state.floor = row["floor"] as? [String: Any]; state.pending = []
            state.fieldRegistration = nil
            state.detectionBoundary = max(state.detectionBoundary, event.time)
        case "measurementCompleted":
            guard let measurement = row["measurement"] as? [String: Any], let id = identifier(measurement["id"]) else { return }
            state.measurements.removeAll { identifier($0["id"]) == id }
            state.measurements.append(measurement)
            if state.measurements.count > 50 { state.measurements.removeFirst() }
            state.pending = []
        case "measurementPoint":
            if number(row["pointCount"]) == 1, let records = row["points"] as? [[String: Any]], let first = records.first,
               let world = point(first["worldMeters"]) { state.pending = [world] }
            else { state.pending = [] }
        case "measurementsCleared": state.measurements = []; state.pending = []
        case "trackingChanged":
            state.tracking = row["tracking"] as? String; state.trackingTime = event.time
            if state.tracking != "normal" {
                state.fieldRegistration = nil
                state.pending = []; state.detectionBoundary = max(state.detectionBoundary, event.time)
            }
        default: break
        }
    }

    /// The recording pins raw detector-tag transforms. No current catalog or live
    /// setting may reinterpret a historical field package during playback.
    private static func fieldTags(_ manifest: [String: Any]) throws -> [ExpectedFieldTag] {
        guard let raw = manifest["fieldDefinition"], !(raw is NSNull) else { return [] }
        guard let descriptor = raw as? [String: Any], let id = identifier(descriptor["id"]),
              let sha = descriptor["packageSha256"] as? String, sha.count == 64,
              sha.allSatisfy({ "0123456789abcdef".contains($0) }),
              let definition = descriptor["definition"] as? [String: Any],
              identifier(definition["id"]) == id,
              let rows = definition["tags"] as? [[String: Any]], rows.count <= 256 else {
            throw TimelineError.invalid("invalid pinned field definition")
        }
        var result = [ExpectedFieldTag](), identities = Set<Int>()
        for row in rows {
            guard let value = number(row["id"]), value.rounded() == value, (0...65535).contains(value),
                  row["family"] as? String == "tag36h11", let size = number(row["poseSizeMeters"]),
                  size > 0, size <= 5, let placement = row["placement"] as? String,
                  ["fixedField", "movable", "clusterMember", "unknown"].contains(placement),
                  identities.insert(Int(value)).inserted else { throw TimelineError.invalid("invalid recorded field tag") }
            guard let rawTransform = row["fieldFromTagColumnMajor"], !(rawTransform is NSNull) else { continue }
            guard placement == "fixedField", let transform = rigidMatrix(rawTransform) else {
                throw TimelineError.invalid("invalid fixed field-tag placement")
            }
            result.append(ExpectedFieldTag(id: Int(value), size: size, fieldFromTag: transform))
        }
        return result
    }
    private static func rigidMatrix(_ raw: Any?) -> simd_float4x4? {
        guard let values = numbers(raw, count: 16) else { return nil }
        var result = matrix_identity_float4x4
        for column in 0..<4 { for row in 0..<4 { result[column][row] = Float(values[column*4+row]) } }
        guard (0..<4).allSatisfy({ c in (0..<4).allSatisfy { result[c][$0].isFinite } }),
              abs(result[0][3]) < 1e-5, abs(result[1][3]) < 1e-5, abs(result[2][3]) < 1e-5,
              abs(result[3][3]-1) < 1e-5 else { return nil }
        let axes = (0..<3).map { c in SIMD3(result[c].x, result[c].y, result[c].z) }
        guard axes.allSatisfy({ abs(simd_length($0)-1) < 1e-4 }),
              abs(simd_dot(axes[0],axes[1])) < 1e-4, abs(simd_dot(axes[0],axes[2])) < 1e-4,
              abs(simd_dot(axes[1],axes[2])) < 1e-4,
              simd_dot(simd_cross(axes[0],axes[1]),axes[2]) > 0.999 else { return nil }
        return result
    }

    private static func usablePose(_ detection: [String: Any]) -> [String: Any]? {
        guard let debug = detection["debug"] as? [String: Any], flag(debug["valid"]) == true,
              let pose = detection["pose"] as? [String: Any], flag(pose["ambiguous"]) == false,
              let translation = numbers(pose["translation"], count: 3), translation[2] > 0.01,
              let rotation = numbers(pose["rotationRowMajor"], count: 9) else { return nil }
        let columns = (0..<3).map { index in SIMD3<Double>(rotation[index], rotation[index+3], rotation[index+6]) }
        guard columns.allSatisfy({ abs(simd_length($0)-1) < 0.05 }),
              abs(simd_dot(columns[0], columns[1])) < 0.05, abs(simd_dot(columns[0], columns[2])) < 0.05,
              abs(simd_dot(columns[1], columns[2])) < 0.05, simd_dot(simd_cross(columns[0], columns[1]), columns[2]) > 0.9 else { return nil }
        return pose
    }
    private static func intersect(_ pixel: CGPoint, pose: [String: Any], source: Geometry) -> SIMD3<Float>? {
        guard let rotation = numbers(pose["rotationRowMajor"], count: 9), let t = numbers(pose["translation"], count: 3) else { return nil }
        let normal = SIMD3<Double>(rotation[2], rotation[5], rotation[8]), center = SIMD3<Double>(t[0],t[1],t[2])
        let k = source.intrinsics
        let ray = SIMD3<Double>((Double(pixel.x)-Double(k[2][0]))/Double(k[0][0]),
                                (Double(pixel.y)-Double(k[2][1]))/Double(k[1][1]), 1)
        let denominator = simd_dot(normal, ray)
        guard abs(denominator) > 1e-8 else { return nil }
        let z = simd_dot(normal, center) / denominator
        guard z.isFinite, z > 0.01 else { return nil }
        return world(ray*z, source: source)
    }
    private static func world(_ optical: SIMD3<Double>, source: Geometry) -> SIMD3<Float>? {
        let result = source.transform * SIMD4<Float>(Float(optical.x), -Float(optical.y), -Float(optical.z), 1)
        let point = SIMD3<Float>(result.x,result.y,result.z)
        return finite(point) ? point : nil
    }
    private static func addAxes(_ pose: [String: Any], source: Geometry, camera: SpatialProjection.Camera,
                                length: Float, id: String, lines: inout [RecordingPlaybackSnapshot.Line]) {
        guard let t = numbers(pose["translation"], count: 3), let r = numbers(pose["rotationRowMajor"], count: 9),
              let start = world(SIMD3<Double>(t[0],t[1],t[2]), source: source) else { return }
        for axis in 0..<3 {
            let end = SIMD3<Double>(t[0]+r[axis]*Double(length), t[1]+r[axis+3]*Double(length), t[2]+r[axis+6]*Double(length))
            if let point = world(end, source: source), let projected = camera.segment(from: start, to: point) {
                let name = ["x","y","z"][axis]
                lines.append(.init(id: "\(id).axis.\(name)", points: projected, label: name.uppercased(), style: "axis-\(name)"))
            }
        }
    }
    private static func addTagHeight(_ detection: [String: Any], event: [String: Any], activeFloor: [String: Any]?,
                                     segment: String, camera: SpatialProjection.Camera, id: String, imperial: Bool,
                                     lines: inout [RecordingPlaybackSnapshot.Line], polygons: inout [RecordingPlaybackSnapshot.Polygon]) {
        guard let height = detection["floorHeight"] as? [String: Any], flag(height["available"]) == true,
              identifier(height["segmentId"]) == segment, identifier(height["frameId"]) == identifier(event["frameId"]),
              let heightTime = number(height["timestamp"]), let eventTime = number(event["timestamp"]), abs(heightTime-eventTime) <= 1e-7,
              let meters = number(height["meters"]), (0...30).contains(meters),
              let source = height["source"] as? String, ["sceneDepth", "tagPose"].contains(source),
              let floorID = identifier(height["floorId"]), let floor = height["floor"] as? [String: Any],
              identifier(floor["id"]) == floorID, flag(floor["operatorConfirmed"]) == true,
              identifier(floor["segmentId"]) == segment,
              let activeFloor, identifier(activeFloor["id"]) == floorID,
              identifier(activeFloor["segmentId"]) == segment, flag(activeFloor["operatorConfirmed"]) == true,
              identifier(activeFloor["frameId"]) == identifier(floor["frameId"]),
              let activeTime = number(activeFloor["timestamp"]), let floorTime = number(floor["timestamp"]), abs(activeTime-floorTime) <= 1e-7,
              flag(activeFloor["levelFloorWithGravity"]) == flag(floor["levelFloorWithGravity"]),
              let start = point(height["floorFootWorldMeters"]), let end = point(height["worldMeters"]),
              abs(start.x-end.x) <= 1e-4, abs(start.z-end.z) <= 1e-4,
              abs(Double(end.y-start.y)-meters) <= max(0.001,meters*1e-4),
              let origin = point(floor["originWorldMeters"]), let normal = point(floor["normalWorld"]), simd_length(normal) > 0,
              let activeOrigin = point(activeFloor["originWorldMeters"]), let activeNormal = point(activeFloor["normalWorld"]),
              simd_length(origin-activeOrigin) <= 1e-5, simd_length(normal-activeNormal) <= 1e-5,
              abs(simd_dot(normal, start-origin))/simd_length(normal) <= 0.001,
              let projected = camera.segment(from: start, to: end) else { return }
        lines.append(.init(id: "\(id).height", points: projected, label: heightText(detection, meters: meters, imperial: imperial), style: "tag-height"))
        addBase(at: start, floor: floor, camera: camera, id: "\(id).base", to: &polygons)
    }
    private static func heightText(_ detection: [String: Any], meters: Double, imperial: Bool) -> String {
        let tag = number(detection["id"]).map { "#\(Int($0)) · " } ?? ""
        return tag + height(meters, imperial: imperial)
    }
    private static func addBase(at center: SIMD3<Float>, floor: [String: Any], camera: SpatialProjection.Camera,
                                id: String, to polygons: inout [RecordingPlaybackSnapshot.Polygon]) {
        guard let normal = point(floor["normalWorld"]), simd_length(normal) > 0.5 else { return }
        let n = simd_normalize(normal)
        let reference: SIMD3<Float> = abs(n.y) > 0.9 ? [1,0,0] : [0,1,0]
        let right = simd_normalize(simd_cross(n, reference))*0.05, forward = simd_normalize(simd_cross(n,right))*0.05
        let vertices = [center-right-forward, center+right-forward, center+right+forward, center-right+forward]
        let points = camera.polygon(vertices)
        if points.count >= 3 { polygons.append(.init(id: id, points: points, label: nil, style: "base")) }
    }
    private static func tagLabel(_ id: Int, detection: [String: Any], event: [String: Any], settings: [String: Any]) -> String {
        let imperial = flag(settings["showImperialHeight"]) ?? true
        var rows = ["#\(id)"]
        if let recorded = detection["floorHeight"] as? [String: Any], flag(recorded["available"]) == true,
           let source = recorded["source"] as? String, ["sceneDepth", "tagPose"].contains(source),
           let meters = number(recorded["meters"]), (0...30).contains(meters) { rows.append("Height \(height(meters, imperial: imperial))") }
        if let ranges = detection["cameraRanges"] as? [String: Any] {
            for (key, available, label) in [("lidarRangeMeters","lidarAvailable","Depth 3D"), ("tagRangeMeters","tagAvailable","Pose 3D")] {
                if flag(ranges[available]) == true, let meters = number(ranges[key]), meters > 0 { rows.append("\(label) \(height(meters, imperial: imperial))") }
            }
            let threshold = number(settings["distanceDeltaThresholdMeters"]) ?? 0.15
            if let delta = number(ranges["distanceDeltaMeters"]), delta > threshold { rows.append("Δ 3D \(height(delta, imperial: imperial))") }
        }
        let orientation = detection["gravityOrientation"] as? [String: Any] ?? [:]
        let contextMatches = ["frameId", "segmentId"].allSatisfy { key in
            guard let raw = orientation[key] else { return true }
            guard let recorded = identifier(raw), let source = identifier(event[key]) else { return false }
            return recorded == source
        }
        let planeLean = flag(orientation["available"]) == true && contextMatches
            ? number(orientation["planeLeanFromVerticalDegrees"] ?? orientation["tiltFromVerticalDegrees"]).flatMap { (0...90).contains($0) ? $0 : nil } : nil
        let uprightRotation = planeLean == nil ? nil
            : number(orientation["uprightRotationClockwiseDegrees"] ?? orientation["twistDegrees"]).flatMap { (-180...180).contains($0) ? $0 : nil }
        let leanText = planeLean.map { String(format: "%.1f°", $0 == 0 ? 0 : $0) } ?? "—"
        let uprightText = uprightRotation.map { String(format: "%+.1f°", $0 == 0 ? 0 : $0) } ?? "—"
        rows.append("Lean \(leanText) · Upright \(uprightText)")
        return rows.joined(separator: "\n")
    }
    private static func height(_ meters: Double, imperial: Bool) -> String {
        HeightDisplayFormatter.string(meters: meters, showImperial: imperial) ?? "—"
    }

    private static func geometry(_ record: [String: Any]) -> Geometry? {
        guard let transformValues = numbers(record["cameraToWorldColumnMajor"], count: 16),
              let calibration = numbers(record["intrinsicsColumnMajor"], count: 9), let size = imageSize(record),
              calibration[0] > 0, calibration[4] > 0 else { return nil }
        var transform = matrix_identity_float4x4, intrinsics = matrix_identity_float3x3
        for column in 0..<4 { for row in 0..<4 { transform[column][row] = Float(transformValues[column*4+row]) } }
        for column in 0..<3 { for row in 0..<3 { intrinsics[column][row] = Float(calibration[column*3+row]) } }
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { transform[column][$0].isFinite } }),
              (0..<3).allSatisfy({ column in (0..<3).allSatisfy { intrinsics[column][$0].isFinite } }),
              abs(transform[0][3]) < 1e-5, abs(transform[1][3]) < 1e-5, abs(transform[2][3]) < 1e-5, abs(transform[3][3]-1) < 1e-5,
              abs(simd_determinant(transform)) > 1e-8 else { return nil }
        return Geometry(transform: transform, intrinsics: intrinsics, imageSize: size)
    }
    private static func imageSize(_ row: [String: Any]) -> CGSize? {
        guard let width = number(row["imageWidth"]), let height = number(row["imageHeight"]),
              width > 0, height > 0, width <= 65535, height <= 65535 else { return nil }
        return CGSize(width: width, height: height)
    }
    private static func imagePoints(_ raw: Any?) -> [CGPoint]? {
        guard let rows = raw as? [Any], rows.count <= 64 else { return nil }
        var result = [CGPoint]()
        for row in rows {
            guard let pair = numbers(row, count: 2) else { return nil }
            result.append(CGPoint(x: pair[0], y: pair[1]))
        }
        return result
    }
    private static func points(_ raw: Any?) -> [SIMD3<Float>]? {
        guard let rows = raw as? [Any], rows.count <= Int(AFSC_MAX_POLYGON_INPUT) else { return nil }
        var result = [SIMD3<Float>]()
        for row in rows { guard let value = point(row) else { return nil }; result.append(value) }
        return result
    }
    private static func point(_ raw: Any?) -> SIMD3<Float>? {
        guard let values = numbers(raw, count: 3) else { return nil }
        let result = SIMD3<Float>(Float(values[0]),Float(values[1]),Float(values[2]))
        return finite(result) ? result : nil
    }
    private static func finite(_ point: SIMD3<Float>) -> Bool { point.x.isFinite && point.y.isFinite && point.z.isFinite }
    private static func identifier(_ raw: Any?) -> String? { guard let value = raw as? String, !value.isEmpty else { return nil }; return value }
    private static func previewMode(_ raw: Any?) -> String? {
        guard let value = raw as? String, ["camera", "depth", "confidence"].contains(value) else { return nil }
        return value
    }
    private static func number(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func flag(_ raw: Any?) -> Bool? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }; return value.boolValue
    }
    private static func numbers(_ raw: Any?, count: Int) -> [Double]? {
        guard let values = raw as? [Any], values.count == count else { return nil }
        let result = values.compactMap(number); return result.count == count ? result : nil
    }
    private static func upperBound(_ count: Int, predicate: (Int) -> Bool) -> Int {
        var lower = 0, upper = count
        while lower < upper { let middle = lower+(upper-lower)/2; if predicate(middle) { lower = middle+1 } else { upper = middle } }
        return lower
    }
    private static func object(_ data: Data, label: String) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TimelineError.invalid("invalid \(label)") }; return result
    }
    private static func records(_ data: Data) throws -> [[String: Any]] {
        guard let text = String(data: data, encoding: .utf8) else { throw TimelineError.invalid("invalid UTF-8 metadata") }
        var result = [[String: Any]]()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            result.append(try object(Data(line.utf8), label: "JSONL record"))
            guard result.count <= recordLimit else { throw TimelineError.invalid("too many metadata records") }
        }
        return result
    }
    private static func readMetadata(_ name: String, directory: Int32) throws -> Data {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw TimelineError.invalid("cannot open \(name)") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size >= 0, before.st_size <= metadataLimit else { throw TimelineError.invalid("\(name) is not bounded regular metadata") }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64*1024), !chunk.isEmpty {
            guard data.count + chunk.count <= metadataLimit else { throw TimelineError.invalid("\(name) exceeds the metadata limit") }; data.append(chunk)
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size, data.count == Int(after.st_size),
              before.st_ino == after.st_ino, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw TimelineError.invalid("\(name) changed while loading")
        }
        return data
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
