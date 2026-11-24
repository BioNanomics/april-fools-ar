import Foundation
import CryptoKit
import CoreFoundation
import simd

enum FieldValue {
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }; return n.doubleValue
    }
    static func numbers(_ value: Any?, _ count: Int) -> [Double]? {
        guard let values = value as? [Any], values.count == count else { return nil }
        let result = values.compactMap(number); return result.count == count ? result : nil
    }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func core(_ matrix: simd_double4x4) -> AFSCMat4 {
        var out = AFSCMat4()
        withUnsafeMutableBytes(of: &out.values) { bytes in
            let values = bytes.bindMemory(to: Double.self)
            for c in 0..<4 { for r in 0..<4 { values[c*4+r] = matrix[c][r] } }
        }; return out
    }
    static func matrix(_ values: Any?) -> simd_double4x4? {
        guard let v = numbers(values, 16) else { return nil }
        let matrix = simd_double4x4(columns: (.init(v[0],v[1],v[2],v[3]),.init(v[4],v[5],v[6],v[7]),.init(v[8],v[9],v[10],v[11]),.init(v[12],v[13],v[14],v[15])))
        var inverse = AFSCMat4()
        return afsc_field_inverse(core(matrix), &inverse) != 0 ? matrix : nil
    }
    static func matrix(_ core: AFSCMat4) -> simd_double4x4 {
        let v = withUnsafeBytes(of: core.values) { Array($0.bindMemory(to: Double.self)) }
        return matrix(v) ?? matrix_identity_double4x4
    }
    static func values(_ matrix: simd_double4x4) -> [Double] { (0..<4).flatMap { c in (0..<4).map { r in matrix[c][r] } } }
    static func pose(_ detection: [String: Any]) -> simd_double4x4? {
        guard let pose = detection["pose"] as? [String: Any],
              let t = numbers(pose["translation"],3), let r = numbers(pose["rotationRowMajor"],9) else { return nil }
        return matrix([r[0],r[3],r[6],0,r[1],r[4],r[7],0,r[2],r[5],r[8],0,t[0],t[1],t[2],1])
    }
    static func optional(_ value: Double?) -> AFSCOptionalDouble { value.map { AFSCOptionalDouble(available: 1, value: $0) } ?? AFSCOptionalDouble() }
    static func value(_ value: AFSCOptionalDouble) -> Double? { value.available == 1 && value.value.isFinite ? value.value : nil }
}

struct FieldTagDefinition {
    let id: Int
    let family, name, placement: String
    let size: Double
    let localizationEligible: Bool
    let fieldFromTag: simd_double4x4?
    let raw: [String: Any]
}

struct FieldDefinition {
    let id, label, program, variant, yaml, hash: String
    let raw: [String: Any]
    let tags: [FieldTagDefinition]
    private let tagsByID: [Int: FieldTagDefinition]
    let floorElevation: Double
    init(_ document: [String: Any], yaml supplied: String? = nil) throws {
        func fail(_ reason: String) -> FieldTextCodec.Failure { .invalid("Field definition: \(reason)") }
        guard FieldValue.number(document["schemaVersion"]) == 1,
              let id = document["id"] as? String, id.range(of: #"^[a-zA-Z0-9._-]{1,100}$"#, options: .regularExpression) != nil,
              let program = document["program"] as? String, ["frc","ftc"].contains(program.lowercased()),
              let game = document["game"] as? String, !game.isEmpty,
              let end = FieldValue.number(document["seasonEndYear"]), end.rounded() == end, (2000...9999).contains(end),
              let start = FieldValue.number(document["seasonStartYear"]), start.rounded() == start, (2000...9999).contains(start), start <= end,
              document["lengthUnit"] as? String == "meter", document["angleUnit"] as? String == "radian",
              document["tagFrame"] as? String == "detector-x-right-y-down-z-in",
              document["coordinateFrame"] as? String == (program.lowercased() == "frc" ? "wpilib-blue-z-up" : "ftc-centered-z-up"),
              let floor = FieldValue.number(document["floorElevationMeters"]),
              let records = document["tags"] as? [[String: Any]], !records.isEmpty, records.count <= 256 else { throw fail("missing/unsupported schema, program, season, floor datum or tags") }
        var parsed = [FieldTagDefinition](), seen = Set<Int>()
        for record in records {
            guard let value = FieldValue.number(record["id"]), value.rounded() == value, (0...65535).contains(value),
                  let family = record["family"] as? String, family == "tag36h11",
                  let size = FieldValue.number(record["poseSizeMeters"]), size > 0, size <= 5,
                  let name = record["name"] as? String, let placement = record["placement"] as? String,
                  ["fixedField","movable","clusterMember","unknown"].contains(placement),
                  let eligibility = record["localizationEligible"] as? NSNumber, CFGetTypeID(eligibility) == CFBooleanGetTypeID() else { throw fail("invalid tag identity, size, placement or eligibility") }
            let tagID = Int(value); guard seen.insert(tagID).inserted else { throw fail("duplicate tag ID \(tagID)") }
            let transform = FieldValue.matrix(record["fieldFromTagColumnMajor"])
            if eligibility.boolValue && (placement != "fixedField" || transform == nil) { throw fail("tag \(tagID) is not a fixed anchor with a valid pose") }
            if placement != "fixedField", !(record["fieldFromTagColumnMajor"] is NSNull || record["fieldFromTagColumnMajor"] == nil) { throw fail("moving/unknown tag \(tagID) cannot have a fixed field pose") }
            if let raw = record["fieldFromTagColumnMajor"], !(raw is NSNull), transform == nil { throw fail("invalid transform for tag \(tagID)") }
            if let suppliedPose = record["fieldPose"] {
                if suppliedPose is NSNull {
                    guard transform == nil else { throw fail("tag \(tagID) fieldPose is null but its transform is available") }
                } else {
                    guard placement == "fixedField", let transform,
                          let pose = suppliedPose as? [String: Any],
                          let translation = FieldValue.numbers(pose["translation"], 3),
                          let quaternion = FieldValue.numbers(pose["quaternion"], 4),
                          abs(quaternion.reduce(0) { $0 + $1 * $1 } - 1) < 1e-5 else {
                        throw fail("tag \(tagID) fieldPose requires finite XYZ, unit WXYZ and a matching fixed transform")
                    }
                    var derived = AFSCMat4()
                    let valid = quaternion.withUnsafeBufferPointer { q in
                        afsc_field_transform_from_pose(AFSCVec3(x: translation[0], y: translation[1], z: translation[2]), q.baseAddress, &derived)
                    }
                    let derivedValues = withUnsafeBytes(of: derived.values) { Array($0.bindMemory(to: Double.self)) }
                    guard valid != 0, zip(derivedValues, FieldValue.values(transform)).allSatisfy({ abs($0 - $1) < 1e-8 }) else {
                        throw fail("tag \(tagID) fieldPose disagrees with its column-major transform")
                    }
                }
            }
            parsed.append(.init(id: tagID, family: family, name: name, placement: placement, size: size, localizationEligible: eligibility.boolValue, fieldFromTag: transform, raw: record))
        }
        let clusters = document["clusters"] as? [[String: Any]] ?? []
        var members = Set<Int>(), clusterIDs = Set<String>()
        for cluster in clusters {
            guard let clusterID = cluster["id"] as? String ?? cluster["name"] as? String,
                  let rows = cluster["members"] as? [[String: Any]], !rows.isEmpty,
                  clusterIDs.insert(clusterID).inserted,
                  cluster["fieldPose"] is NSNull || cluster["fieldPose"] == nil,
                  cluster["localizationEligible"] as? Bool != true else { throw fail("invalid, duplicate or unsupported fixed cluster") }
            for row in rows {
                guard let value = FieldValue.number(row["id"] ?? row["tagId"]), value.rounded() == value, (0...65535).contains(value),
                      let tag = parsed.first(where: { $0.id == Int(value) }), tag.placement == "clusterMember",
                      members.insert(Int(value)).inserted, tag.raw["clusterId"] as? String == clusterID,
                      FieldValue.matrix(row["clusterFromTagColumnMajor"]) != nil else { throw fail("invalid membership/transform in cluster \(clusterID)") }
            }
        }
        guard parsed.filter({ $0.placement == "clusterMember" }).allSatisfy({ members.contains($0.id) }) else { throw fail("cluster member has no parent geometry") }
        var clean = document; clean.removeValue(forKey: "yaml"); clean.removeValue(forKey: "packageSha256")
        let yaml = try supplied ?? FieldTextCodec.yaml(clean)
        if let supplied {
            let decoded = try FieldTextCodec.parse(supplied)
            guard NSDictionary(dictionary: decoded).isEqual(to: clean) else { throw fail("YAML payload does not match parsed package") }
        }
        self.id = id; self.program = program.lowercased(); self.variant = document["variant"] as? String ?? "standard"
        self.label = "\(program.uppercased()) \(Int(start) == Int(end) ? String(Int(end)) : "\(Int(start))–\(Int(end))") \(game) · \(self.variant)"
        self.yaml = yaml; self.hash = FieldValue.hash(yaml); self.raw = clean; self.tags = parsed; self.tagsByID = Dictionary(uniqueKeysWithValues: parsed.map { ($0.id,$0) }); self.floorElevation = floor
        if let expected = document["packageSha256"] as? String, expected != self.hash { throw fail("package hash does not match YAML bytes") }
    }
    func tag(_ id: Int, family: String = "tag36h11") -> FieldTagDefinition? { guard let tag = tagsByID[id], tag.family == family else { return nil }; return tag }
    var descriptor: [String: Any] { ["id": id, "label": label, "program": program, "season": raw["seasonEndYear"] ?? NSNull(), "variant": variant, "tagCount": tags.count, "packageSha256": hash] }
}

final class FieldDefinitionStore {
    static let shared = FieldDefinitionStore()
    private(set) var packages = [FieldDefinition]()
    private(set) var error: String?
    let importedDirectory: URL
    init(catalogURL: URL? = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "FieldDefinitions"), importedDirectory: URL? = nil) {
        self.importedDirectory = importedDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("AprilFoolsAR/fields", isDirectory: true)
        do {
            if let catalogURL {
                let data = try Data(contentsOf: catalogURL)
                guard data.count <= 8 * FieldTextCodec.maximumBytes,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["packages"] as? [[String: Any]], rows.count <= 64 else { throw FieldTextCodec.Failure.invalid("Invalid bundled field catalog") }
                for row in rows { packages.append(try FieldDefinition(row, yaml: row["yaml"] as? String)) }
            } else { error = "Bundled field catalog is unavailable." }
            if FileManager.default.fileExists(atPath: self.importedDirectory.path) {
                for url in try FileManager.default.contentsOfDirectory(at: self.importedDirectory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "yaml" }) {
                    let data = try Data(contentsOf: url); guard data.count <= FieldTextCodec.maximumBytes else { continue }
                    if let text = String(data: data, encoding: .utf8), let field = try? FieldDefinition(FieldTextCodec.parse(text), yaml: text), !packages.contains(where: { $0.id == field.id }) { packages.append(field) }
                }
            }
        } catch { self.error = error.localizedDescription; packages = [] }
    }
    func find(_ id: String) -> FieldDefinition? { packages.first { $0.id == id } }
    func importDefinition(_ text: String) throws -> FieldDefinition {
        let field = try FieldDefinition(FieldTextCodec.parse(text))
        if let old = find(field.id) {
            guard old.hash == field.hash || NSDictionary(dictionary: old.raw).isEqual(to: field.raw) else { throw FieldTextCodec.Failure.invalid("That package ID already exists. Use a new ID/revision for changed geometry.") }; return old
        }
        try FileManager.default.createDirectory(at: importedDirectory, withIntermediateDirectories: true)
        try Data(field.yaml.utf8).write(to: importedDirectory.appendingPathComponent(field.id + ".yaml"), options: .atomic)
        packages.append(field); return field
    }
}

struct FieldPlacement {
    let id: Int
    let corners: [SIMD3<Float>]
    let center, normal: SIMD3<Float>
    let seen: Bool
}

/// Capture-queue-owned facts, bounded by distinct tags rather than walk duration.
final class FieldWalkState {
    private(set) var definition: FieldDefinition?
    private(set) var alignment = "unaligned"
    private(set) var reason = "Choose a field definition."
    private(set) var checks = [String: Any]()
    private(set) var warnings = [String]()
    private(set) var worldFromField: simd_double4x4?
    private(set) var anchorID: Int?
    private(set) var alignmentSegment: String?
    private var candidate: (id: Int, start: Double, last: Double, count: Int)?
    private var manualRequested: Int?
    private var latestCandidate: (tag: FieldTagDefinition, world: simd_double4x4, check: AFSCAnchorCheck, segment: String)?
    private var entries = [String: [String: Any]]()
    private var history = [[String: Any]]()
    private var recording = false
    private var walkID: String?
    private var recentEventIDs = [String]()
    private var recentEventSet = Set<String>()
    private var omittedTagObservations = 0
    private var omittedRegistrationEvents = 0
    private var observationCount = 0
    private var walkStartedTimestamp: Double?
    private var walkLastTimestamp: Double?
    private var eventOrdinal = 0
    private var sourceTimestamp = 0.0
    private var sourceSegment = ""
    private var lastWarningEventTime = -Double.infinity
    private(set) var floorID: String?
    // Conservative initial inspection settings; recorded with each walk and not empirical accuracy claims.
    static let heightTolerance = 0.10
    static let tiltTolerance = 5.0 * Double.pi / 180
    static let gravityTolerance = 7.0 * Double.pi / 180
    static let positionTolerance = 0.15
    static let maximumSeenTags = 512
    static let maximumRegistrationEvents = 128
    private static let deduplicationWindow = 128
    var onEvent: (([String: Any]) -> Void)?
    func select(_ field: FieldDefinition) { definition = field; resetInventory(); invalidate("Field definition selected.") }
    func resetInventory() {
        entries = [:]; history = []; warnings = []; walkID = nil; eventOrdinal = 0; lastWarningEventTime = -.infinity
        recentEventIDs = []; recentEventSet = []; omittedTagObservations = 0; omittedRegistrationEvents = 0; observationCount = 0
        walkStartedTimestamp = nil; walkLastTimestamp = nil
    }
    func beginWalk(_ id: String, timestamp: Double = 0, segment: String? = nil) { resetInventory(); walkID = id; recording = true; walkStartedTimestamp = timestamp; walkLastTimestamp = timestamp; emit("fieldWalkStarted", timestamp: timestamp, segment: segment ?? alignmentSegment ?? "") }
    func stopWalk() { recording = false }
    func invalidate(_ why: String, segment: String? = nil, timestamp: Double = 0) {
        alignment = "unaligned"; reason = why; worldFromField = nil; anchorID = nil; alignmentSegment = nil; candidate = nil; latestCandidate = nil; manualRequested = nil; checks = [:]; floorID = nil
        emit("fieldRegistrationInvalidated", timestamp: timestamp, segment: segment ?? "", extra: ["reason": why])
    }
    func suspend(_ why: String, timestamp: Double, segment: String) {
        guard worldFromField != nil else { return }
        invalidate(why, segment: segment, timestamp: timestamp)
    }
    func recheck() { invalidate("Point at a fixed tag to recheck alignment.") }
    func requestManual() throws {
        guard let last = latestCandidate, last.check.status == AFSC_FIELD_UNAVAILABLE,
              last.check.tilt_status != AFSC_FIELD_FAIL, last.check.gravity_status != AFSC_FIELD_FAIL else {
            throw FieldTextCodec.Failure.invalid("Manual alignment is available only for a qualified fixed tag with unavailable height, never failed checks.")
        }
        manualRequested = last.tag.id; reason = "Manual unverified alignment requested; keep the tag in view."
    }
    private func emit(_ type: String, timestamp: Double, segment: String, extra: [String: Any] = [:]) {
        eventOrdinal += 1
        var event: [String: Any] = ["type": type, "timestamp": timestamp, "segmentId": segment, "fieldEventOrdinal": eventOrdinal,
            "field": registrationSnapshot, "packageId": definition?.id as Any? ?? NSNull(), "packageSha256": definition?.hash as Any? ?? NSNull()]
        event.merge(extra) { _, new in new }; onEvent?(event)
        if recording {
            history.append(event)
            if history.count > Self.maximumRegistrationEvents { history.removeFirst(); omittedRegistrationEvents += 1 }
        }
    }
    var registrationSnapshot: [String: Any] {
        ["policyVersion": 1, "alignment": alignment, "reason": reason, "anchorId": anchorID as Any? ?? NSNull(), "segmentId": alignmentSegment as Any? ?? NSNull(),
         "worldFromFieldColumnMajor": worldFromField.map(FieldValue.values) as Any? ?? NSNull(), "checks": checks, "floorId": floorID as Any? ?? NSNull(),
         "heightToleranceMeters": Self.heightTolerance, "tiltToleranceRadians": Self.tiltTolerance, "gravityToleranceRadians": Self.gravityTolerance,
         "positionToleranceMeters": Self.positionTolerance, "accuracyValidated": false]
    }
    func process(_ detections: [[String: Any]], metadata: [String: Any], now: Double, settings: TagDebugSettings, allowRegistration: Bool = true) {
        guard let frame = metadata["frameId"] as? String, !frame.isEmpty, frame.utf8.count <= 256,
              let segment = metadata["segmentId"] as? String, !segment.isEmpty, segment.utf8.count <= 256,
              let timestamp = FieldValue.number(metadata["timestamp"]), let camera = FieldValue.matrix(metadata["cameraToWorldColumnMajor"]) else { return }
        let field = definition
        sourceTimestamp = timestamp; sourceSegment = segment
        let normal = metadata["tracking"] as? String == "normal", fresh = now >= timestamp && now - timestamp <= 0.4
        if allowRegistration, !normal, worldFromField != nil { suspend("Tracking is unavailable; recheck alignment.", timestamp: timestamp, segment: segment) }
        let sourceFloor = metadata["floorSnapshot"] as? [String: Any]
        let nextFloorID = sourceFloor?["id"] as? String
        if allowRegistration, worldFromField != nil, alignmentSegment != segment || nextFloorID != floorID { invalidate("Coordinate segment or confirmed field floor changed.", segment: segment, timestamp: timestamp) }
        let eventID = segment + ":" + frame
        if recentEventSet.contains(eventID) { return }
        recentEventIDs.append(eventID); recentEventSet.insert(eventID)
        if recentEventIDs.count > Self.deduplicationWindow { recentEventSet.remove(recentEventIDs.removeFirst()) }
        if recording { walkLastTimestamp = max(walkLastTimestamp ?? timestamp, timestamp) }
        var frameTagKeys = Set<String>()
        for detection in detections {
            guard let value = FieldValue.number(detection["id"]), value.rounded() == value, (0...65535).contains(value) else { continue }
            let id = Int(value)
            let family = detection["family"] as? String ?? "tag36h11"
            guard !family.isEmpty, family.utf8.count <= 31 else { continue }
            let tag = field?.tag(id, family: family)
            let key = family + ":" + String(id), validFamily = tag != nil
            guard frameTagKeys.insert(key).inserted else { continue }
            let optical = FieldValue.pose(detection), pose = detection["pose"] as? [String: Any] ?? [:]
            let debug = detection["debug"] as? [String: Any] ?? [:]
            let acceptableStatus = ["valid","missingDepth"].contains(debug["status"] as? String ?? "")
            let usable = allowRegistration && normal && fresh && optical != nil && pose["ambiguous"] as? Bool == false && acceptableStatus &&
                (FieldValue.number(pose["rangeMeters"]) ?? .infinity) <= settings.maxDistanceMeters &&
                (FieldValue.number(pose["reprojectionRMSEPixels"]) ?? .infinity) <= settings.maxReprojectionErrorPixels &&
                (FieldValue.number(pose["planeAngleDegrees"]) ?? .infinity) <= settings.maxViewingIncidenceDegrees &&
                (FieldValue.number(detection["decisionMargin"]) ?? 0) > 0 && FieldValue.number(detection["hamming"]) == 0
            var worldTag: simd_double4x4?
            if let optical { var out = AFSCMat4(); if afsc_field_observed_tag(FieldValue.core(camera), FieldValue.core(optical), &out) != 0 { worldTag = FieldValue.matrix(out) } }
            let height = detection["floorHeight"] as? [String: Any] ?? [:]
            let orientation = detection["gravityOrientation"] as? [String: Any] ?? [:]
            let observedHeight = height["available"] as? Bool == true ? FieldValue.number(height["meters"]) : nil
            let appliedSize = FieldValue.number(pose["tagSizeMeters"])
            let sizeConflict = tag.map { abs((appliedSize ?? $0.size) - $0.size) > max(0.00001, $0.size * 0.03) } ?? false
            if recording {
                let accepted = usable && !sizeConflict
                observationCount += 1
                // Reserve space for every expected tag, so a crowded discovered
                // inventory cannot label a known sighting as `notSeen`.
                let discoveredCapacity = Self.maximumSeenTags - (field?.tags.count ?? 0)
                let newDiscoveredTagAtCapacity = entries[key] == nil && !validFamily &&
                    entries.values.filter { $0["expected"] as? Bool == false }.count >= discoveredCapacity
                if newDiscoveredTagAtCapacity || (entries[key] == nil && entries.count >= Self.maximumSeenTags) {
                    omittedTagObservations += 1
                    warn("Tag summary capacity reached; additional unknown tags are not retained.")
                } else {
                    var row = entries[key] ?? ["id": id, "family": family]
                    row["count"] = (row["count"] as? Int ?? 0) + 1
                    row["acceptedCount"] = (row["acceptedCount"] as? Int ?? 0) + (accepted ? 1 : 0)
                    row["rejectedCount"] = (row["rejectedCount"] as? Int ?? 0) + (accepted ? 0 : 1)
                    row["firstSeen"] = min(FieldValue.number(row["firstSeen"]) ?? timestamp, timestamp)
                    row["lastSeen"] = max(FieldValue.number(row["lastSeen"]) ?? timestamp, timestamp)
                    row["name"] = tag?.name ?? "Discovered tag"; row["frameId"] = frame; row["segmentId"] = segment
                    row["status"] = "seen"; row["expected"] = validFamily; row["placement"] = tag?.placement ?? "unknown"
                    row["nominalTagDefinition"] = tag?.raw as Any? ?? NSNull()
                    row["nominalCoordinateFrame"] = field?.raw["coordinateFrame"] as Any? ?? NSNull()
                    row["nominalPosition"] = tag?.fieldFromTag.map { [$0[3].x,$0[3].y,$0[3].z] } as Any? ?? NSNull()
                    row["expectedHeightMeters"] = tag?.raw["expectedHeightMeters"] ?? NSNull()
                    row["expectedTiltDegrees"] = tag.flatMap { FieldValue.number($0.raw["expectedTiltRadians"]) }.map { $0 * 180 / .pi } as Any? ?? NSNull()
                    row["observedHeightMeters"] = observedHeight as Any? ?? NSNull(); row["observedTiltDegrees"] = orientation["tiltFromVerticalDegrees"] ?? NSNull()
                    row["timestamp"] = timestamp; row["poseSizeMeters"] = appliedSize as Any? ?? NSNull()
                    row["tagSizeResolution"] = detection["tagSizeResolution"] ?? NSNull()
                    row["poseSizeSource"] = pose["tagSizeSource"] as? String ?? "unavailable"
                    row["reason"] = field == nil ? "No field definition selected; nominal field position is unavailable." : !validFamily ? "ID is unknown to this field definition." : sizeConflict ? "Applied print size differs from reference; placement is unresolved." : tag?.fieldFromTag == nil ? "Moving/unknown target has no fixed nominal position." : "Observed; placement is an estimate."
                    row["quality"] = ["usable": accepted, "tracking": metadata["tracking"] as? String ?? "unavailable", "fresh": fresh,
                        "frameAgeSeconds": now - timestamp, "poseAmbiguous": pose["ambiguous"] as? Bool ?? true,
                        "status": debug["status"] as? String ?? "unavailable", "printSizeConflict": sizeConflict,
                        "decisionMargin": FieldValue.number(detection["decisionMargin"]) as Any? ?? NSNull(),
                        "hamming": FieldValue.number(detection["hamming"]) as Any? ?? NSNull(),
                        "reprojectionRMSEPixels": FieldValue.number(pose["reprojectionRMSEPixels"]) as Any? ?? NSNull()]
                    row["cameraRelativePosition"] = FieldValue.numbers(pose["translation"], 3) as Any? ?? NSNull()
                    row["cameraRelativeCoordinateFrame"] = "optical-x-right-y-down-z-forward"
                    row["observedWorldPosition"] = accepted ? worldTag.map { [$0[3].x,$0[3].y,$0[3].z] } as Any? ?? NSNull() : NSNull()
                    row["worldCoordinateFrame"] = "ARKit-gravity-y-up; local to segmentId"
                    row["observedPosition"] = NSNull()
                    row["observedCoordinateFrame"] = field?.raw["coordinateFrame"] as Any? ?? NSNull()
                    row["registration"] = NSNull(); row["registrationAnchorId"] = NSNull(); row["registrationAssumption"] = NSNull()
                    row["comparisonStatus"] = "unavailable"; row["positionDifferenceMeters"] = NSNull(); row["orientationDifferenceRadians"] = NSNull()
                    if accepted, let worldTag, let worldFromField, alignmentSegment == segment {
                        let position = simd_inverse(worldFromField) * worldTag
                        row["observedPosition"] = [position[3].x,position[3].y,position[3].z]
                        row["registration"] = ["alignment": alignment, "anchorId": anchorID as Any? ?? NSNull(), "segmentId": segment,
                            "worldFromFieldColumnMajor": FieldValue.values(worldFromField), "accuracyValidated": false]
                        row["registrationAnchorId"] = anchorID as Any? ?? NSNull(); row["registrationAssumption"] = "single-tag anchor; not independent survey truth"
                        row["comparisonStatus"] = id == anchorID ? "assumed-anchor" : "independent-of-initial-anchor-only"
                        if id == anchorID { row["reason"] = "This tag is the assumed anchor and cannot certify its own field placement." }
                        if let reference = tag?.fieldFromTag {
                            let delta = simd_inverse(reference) * position
                            row["positionDifferenceMeters"] = simd_length(SIMD3(delta[3].x,delta[3].y,delta[3].z))
                            row["orientationDifferenceRadians"] = acos(min(1,max(-1,(delta[0].x+delta[1].y+delta[2].z-1)/2)))
                        }
                    }
                    row["accuracyValidated"] = false
                    // Keep the complete numeric result and its original context,
                    // including unavailable/null values and detailed rejection
                    // reasons. The settings/floor belong to this source event,
                    // never the UI's later state. No image or depth files are kept.
                    let sourceKeys = ["frameId", "segmentId", "timestamp", "family", "imageWidth", "imageHeight", "pixelFormat",
                        "intrinsicsColumnMajor", "cameraToWorldColumnMajor", "displayTransform", "displayZoom", "previewDisplayTransform",
                        "viewportWidth", "viewportHeight", "interfaceOrientation", "tracking", "trackingReason",
                        "analysisSkippedFramesTotal", "targetAnalysisHz", "maxAnalysisInFlight", "recordingId", "poseEstimation",
                        "debugSettings", "calculationCore", "fieldPackageId", "fieldPackageSha256", "floorSnapshot",
                        "latencyMilliseconds", "analysisSucceeded", "detectorError", "fieldProcessingAgeSeconds", "fieldRegistrationAllowed"]
                    let source = Dictionary(uniqueKeysWithValues: sourceKeys.map { ($0, metadata[$0] ?? NSNull()) })
                    let keys = ["frameId", "segmentId", "timestamp", "observedWorldPosition", "worldCoordinateFrame",
                        "observedPosition", "observedCoordinateFrame", "cameraRelativePosition", "cameraRelativeCoordinateFrame",
                        "observedHeightMeters", "observedTiltDegrees", "poseSizeMeters", "poseSizeSource", "quality",
                        "registration", "registrationAnchorId", "comparisonStatus", "accuracyValidated"]
                    var observation = Dictionary(uniqueKeysWithValues: keys.compactMap { key in row[key].map { (key, $0) } })
                    observation["detection"] = detection
                    observation["source"] = source
                    row["latestObservation"] = observation
                    if accepted { row["latestUsableObservation"] = observation }
                    entries[key] = row
                }
            }
            guard let field, let tag, validFamily, tag.localizationEligible, let reference = tag.fieldFromTag, let worldTag, usable else { continue }
            var input = AFSCAnchorInput()
            input.fixed_reference = 1; input.pose_usable = usable ? 1 : 0; input.same_segment = 1
            input.floor_datum_available = observedHeight != nil && height["floorId"] as? String == nextFloorID && (height["segmentId"] as? String) == segment ? 1 : 0
            input.field_from_tag = FieldValue.core(reference); input.world_from_tag = FieldValue.core(worldTag); input.field_floor_z_m = field.floorElevation
            input.observed_height_m = FieldValue.optional(observedHeight); input.height_tolerance_m = Self.heightTolerance
            input.tilt_tolerance_rad = Self.tiltTolerance; input.gravity_tolerance_rad = Self.gravityTolerance
            let check = afsc_field_check_anchor(&input)
            if worldFromField == nil {
                if let active = candidate, active.id != id, timestamp - active.last <= 0.4 { continue }
                latestCandidate = (tag, worldTag, check, segment); checks = checkDictionary(check)
                if sizeConflict { reason = "Tag \(id): applied size differs from the selected definition; check the print size and sizing mode."; warn(reason); candidate = nil; continue }
                if check.status == AFSC_FIELD_FAIL { reason = warning(id, check); warn(reason); candidate = nil; manualRequested = nil; continue }
                let manual = manualRequested == id && check.status == AFSC_FIELD_UNAVAILABLE && check.tilt_status != AFSC_FIELD_FAIL && check.gravity_status != AFSC_FIELD_FAIL
                guard check.status == AFSC_FIELD_PASS || manual else { reason = "Tag \(id): height unverified. Select and confirm the field floor in Measure, or explicitly align without height verification."; candidate = nil; continue }
                if let old = candidate, old.id == id, timestamp > old.last, timestamp - old.last <= 0.4 {
                    candidate = (id, old.start, timestamp, old.count + 1)
                } else { candidate = (id,timestamp,timestamp,1) }
                guard let candidate, candidate.count >= 3, timestamp - candidate.start >= 0.2 else { reason = "Hold tag \(id) in view to check a stable first anchor."; continue }
                var transform = AFSCMat4()
                guard afsc_field_registration(FieldValue.core(worldTag), FieldValue.core(reference), &transform) != 0 else { reason = "Field heading is unresolved from this tag orientation."; continue }
                worldFromField = FieldValue.matrix(transform); alignmentSegment = segment; anchorID = id; floorID = nextFloorID
                alignment = "provisional"; reason = manual ? "Unverified manual anchor #\(id); height was unavailable." : "Aligned from #\(id); height/tilt match. Single-tag position and heading remain assumed."
                manualRequested = nil
                if recording, var row = entries[key] {
                    row["comparisonStatus"] = "assumed-anchor"; row["reason"] = "This tag is the assumed anchor and cannot certify its own field placement."
                    entries[key] = row
                }
                emit("fieldRegistrationChanged", timestamp: timestamp, segment: segment, extra: ["frameId": frame])
            } else if let worldFromField, alignmentSegment == segment {
                let predicted = worldFromField * reference
                let error = simd_length(SIMD3<Double>(predicted[3].x-worldTag[3].x,predicted[3].y-worldTag[3].y,predicted[3].z-worldTag[3].z))
                let delta = simd_inverse(predicted) * worldTag
                let orientationError = acos(min(1,max(-1,(delta[0].x+delta[1].y+delta[2].z-1)/2)))
                if error > Self.positionTolerance || orientationError > Self.gravityTolerance || check.status == AFSC_FIELD_FAIL {
                    let newlyDegraded = alignment != "degraded"
                    alignment = "degraded"; reason = "Tag \(id) disagrees with anchor #\(anchorID ?? id) by \(String(format: "%.1f", error*100)) cm / \(String(format: "%.1f", orientationError*180 / .pi))°. Recheck the field/anchor; field geometry was not moved."
                    if check.status == AFSC_FIELD_FAIL { checks = checkDictionary(check); reason += " " + warning(id, check) }
                    warn(reason); if newlyDegraded { emit("fieldRegistrationChanged", timestamp: timestamp, segment: segment, extra: ["frameId": frame, "positionDifferenceMeters": error, "orientationDifferenceRadians": orientationError]) }
                }
            }
        }
    }
    private func warn(_ warning: String) {
        guard !warnings.contains(warning) else { return }
        warnings.append(warning); if warnings.count > 30 { warnings.removeFirst() }
        if recording && sourceTimestamp - lastWarningEventTime >= 1 {
            lastWarningEventTime = sourceTimestamp
            var snapshot = registrationSnapshot; snapshot["reason"] = warning
            emit("fieldAnchorWarning", timestamp: sourceTimestamp, segment: sourceSegment, extra: ["field": snapshot, "reason": warning])
        }
    }
    private func checkDictionary(_ c: AFSCAnchorCheck) -> [String: Any] {
        func state(_ s: AFSCFieldCheckState) -> String { s == AFSC_FIELD_PASS ? "pass" : s == AFSC_FIELD_FAIL ? "fail" : "unavailable" }
        return ["height": ["expected": FieldValue.value(c.expected_height_m) as Any? ?? NSNull(), "observed": FieldValue.value(c.observed_height_m) as Any? ?? NSNull(), "difference": FieldValue.value(c.height_difference_m) as Any? ?? NSNull(), "tolerance": Self.heightTolerance, "status": state(c.height_status)],
                "tilt": ["expected": FieldValue.value(c.expected_tilt_rad).map { $0*180 / .pi } as Any? ?? NSNull(), "observed": FieldValue.value(c.observed_tilt_rad).map { $0*180 / .pi } as Any? ?? NSNull(), "tolerance": Self.tiltTolerance*180 / .pi, "status": state(c.tilt_status)],
                "gravity": ["difference": FieldValue.value(c.gravity_difference_rad).map { $0*180 / .pi } as Any? ?? NSNull(), "tolerance": Self.gravityTolerance*180 / .pi, "status": state(c.gravity_status)]]
    }
    private func warning(_ id: Int, _ c: AFSCAnchorCheck) -> String {
        func n(_ v: AFSCOptionalDouble, _ scale: Double) -> String { FieldValue.value(v).map { String(format: "%.1f", $0*scale) } ?? "unavailable" }
        return "Tag \(id) · \(definition?.label ?? "field"): expected center height \(n(c.expected_height_m,100)) cm, observed \(n(c.observed_height_m,100)) cm (±\(Int(Self.heightTolerance*100)) cm); expected tilt \(n(c.expected_tilt_rad,180 / .pi))°, observed \(n(c.observed_tilt_rad,180 / .pi))° (±5°). Gravity/printed-up difference \(n(c.gravity_difference_rad,180 / .pi))° (±7°). Not aligned from this tag. Check field/variant, floor, mounting and print size."
    }
    var status: [String: Any] {
        let rows = entries.values.sorted {
            let a = FieldValue.number($0["id"]) ?? 0, b = FieldValue.number($1["id"]) ?? 0
            return a == b ? ($0["family"] as? String ?? "") < ($1["family"] as? String ?? "") : a < b
        }
        let notSeen = (definition?.tags ?? []).filter { entries[$0.family + ":" + String($0.id)] == nil }.map { tag -> [String: Any] in
            ["id": tag.id, "family": tag.family, "name": tag.name, "status": "notSeen", "expected": true,
             "placement": tag.placement, "localizationEligible": tag.localizationEligible,
             "nominalTagDefinition": tag.raw,
             "nominalPosition": tag.fieldFromTag.map { [$0[3].x,$0[3].y,$0[3].z] } as Any? ?? NSNull(),
             "nominalCoordinateFrame": definition?.raw["coordinateFrame"] as Any? ?? NSNull(),
             "observedPosition": NSNull(), "poseSizeMeters": tag.size,
             "reason": "Expected by the selected definition, but not observed in this walk. This does not establish physical absence."]
        }
        var value = registrationSnapshot
        value["packageId"] = definition?.id as Any? ?? NSNull(); value["label"] = definition?.label as Any? ?? NSNull()
        value["packageSha256"] = definition?.hash as Any? ?? NSNull(); value["seenTags"] = rows
        value["notSeenTags"] = notSeen; value["notSeenCount"] = notSeen.count
        value["expectedSeenCount"] = rows.filter { $0["expected"] as? Bool == true }.count
        value["discoveredCount"] = rows.filter { $0["expected"] as? Bool == false }.count
        value["seenCount"] = rows.count; value["expectedCount"] = definition?.tags.count ?? 0; value["warnings"] = warnings
        value["inventoryCapacity"] = ["usedEntries": rows.count, "limitEntries": Self.maximumSeenTags, "observationCount": observationCount]
        value["summaryTruncated"] = omittedTagObservations > 0 || omittedRegistrationEvents > 0
        value["omittedTagObservationCount"] = omittedTagObservations; value["historyOmittedCount"] = omittedRegistrationEvents
        value["coordinateFrame"] = definition?.raw["coordinateFrame"] ?? NSNull(); value["walkId"] = walkID as Any? ?? NSNull(); value["recording"] = recording; value["candidateId"] = latestCandidate?.tag.id as Any? ?? NSNull(); return value
    }
    var summary: [String: Any] {
        ["schemaVersion": 1, "summaryVersion": 2, "field": status, "registrationEvents": history,
         "fieldDefinition": definition.map { ["id": $0.id, "label": $0.label, "packageSha256": $0.hash,
             "source": $0.raw["source"] as Any? ?? NSNull(), "coordinateFrame": $0.raw["coordinateFrame"] as Any? ?? NSNull()] } as Any? ?? NSNull(),
         "coordinateFrame": definition?.raw["coordinateFrame"] as Any? ?? NSNull(), "lengthUnit": "meter",
         "clock": "ARFrame.timestamp seconds since system boot",
         "startedTimestamp": walkStartedTimestamp as Any? ?? NSNull(), "lastTimestamp": walkLastTimestamp as Any? ?? NSNull(),
         "durationSeconds": max(0, (walkLastTimestamp ?? 0) - (walkStartedTimestamp ?? 0)),
         "inventoryCapacity": ["usedEntries": entries.count, "limitEntries": Self.maximumSeenTags, "observationCount": observationCount],
         "summaryTruncated": omittedTagObservations > 0 || omittedRegistrationEvents > 0,
         "historyOmittedCount": omittedRegistrationEvents, "omittedTagObservationCount": omittedTagObservations,
         "retention": "Per-tag counts, latest complete numeric detection/source context and latest usable observation; at most 128 recent registration events. No complete frame history or image/depth files. Discovered tags have expected=false in field.seenTags.",
         "notSeenMeaning": "Expected by the selected definition and not observed; physical absence is not established.",
         "accuracyValidated": false]
    }
    func placements() -> [FieldPlacement] {
        guard let definition, let worldFromField else { return [] }
        return definition.tags.compactMap { tag in
            guard let transform = tag.fieldFromTag else { return nil }
            let world = worldFromField * transform, s = tag.size / 2
            func point(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Float> { let p = world * SIMD4<Double>(x,y,z,1); return SIMD3(Float(p.x),Float(p.y),Float(p.z)) }
            return .init(id: tag.id, corners: [point(-s,s,0),point(s,s,0),point(s,-s,0),point(-s,-s,0)], center: point(0,0,0), normal: point(0,0,-s), seen: entries[tag.family + ":" + String(tag.id)] != nil)
        }
    }
}
