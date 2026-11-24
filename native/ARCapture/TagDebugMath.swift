import Foundation
import CoreVideo
import CoreFoundation
import simd

enum TagDebugError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

// BEGIN GENERATED FIELD SIZE CATALOG — edit fields/size-standards.yaml instead.
enum TagFieldCatalog {
    struct Preset {
        let mode: String
        let year: Int
        let reference: Double
        let game: String
        let requiresKnownID: Bool
        let widths: [Int: Double]
    }
    static let presets: [Preset] = [
        Preset(mode: "ftc", year: 2024, reference: 0.0508, game: "CENTERSTAGE", requiresKnownID: true, widths: [1: 0.0508, 2: 0.0508, 3: 0.0508, 4: 0.0508, 5: 0.0508, 6: 0.0508, 7: 0.127, 8: 0.0508, 9: 0.0508, 10: 0.127]),
        Preset(mode: "ftc", year: 2025, reference: 0.1016, game: "INTO THE DEEP", requiresKnownID: false, widths: [:]),
        Preset(mode: "ftc", year: 2026, reference: 0.1651, game: "DECODE", requiresKnownID: false, widths: [:]),
        Preset(mode: "ftc", year: 2027, reference: 0.08255, game: "BIOBUZZ", requiresKnownID: false, widths: [:]),
        Preset(mode: "frc", year: 2024, reference: 0.1651, game: "CRESCENDO", requiresKnownID: false, widths: [:]),
        Preset(mode: "frc", year: 2025, reference: 0.1651, game: "REEFSCAPE", requiresKnownID: false, widths: [:]),
        Preset(mode: "frc", year: 2026, reference: 0.1651, game: "REBUILT", requiresKnownID: false, widths: [:]),
    ]
    static let autoStandards: [(edge: Double, label: String, tolerance: Double)] = [
        (0.0508, "FTC 2 in", 0.1),
        (0.08255, "FTC BIOBUZZ 3.25 in", 0.1),
        (0.1016, "FTC 4 in", 0.1),
        (0.127, "FTC 5 in", 0.1),
        (0.1524, "FTC sample 6 in", 0.03),
        (0.1651, "FRC / FTC 6.5 in", 0.03),
    ]
    static func defaultYear(mode: String) -> Int { mode == "ftc" ? 2027 : (mode == "frc" ? 2026 : 0) }
    static func referenceWidth(mode: String, year: Int) -> Double? {
        presets.first { $0.mode == mode && $0.year == year }?.reference
    }
    static func width(mode: String, year: Int, tagID: Int?) -> Double? {
        guard let preset = presets.first(where: { $0.mode == mode && $0.year == year }) else { return nil }
        if preset.requiresKnownID { return tagID.flatMap { preset.widths[$0] } }
        return preset.reference
    }
    static func label(mode: String, year: Int) -> String {
        "\(mode.uppercased()) \(presets.first { $0.mode == mode && $0.year == year }?.game ?? "") \(year)"
    }
}
// END GENERATED FIELD SIZE CATALOG

struct TagDebugSettings: Codable, Equatable {
    static let frcTagSizeMeters = TagFieldCatalog.referenceWidth(mode: "frc", year: TagFieldCatalog.defaultYear(mode: "frc"))!
    static let ftcTagSizeMeters = TagFieldCatalog.referenceWidth(mode: "ftc", year: TagFieldCatalog.defaultYear(mode: "ftc"))!
    var tagSizeMeters = frcTagSizeMeters
    var tagSizeMode = "auto"
    var competitionYear = 0
    var maxDistanceMeters = 5.0
    var maxPlaneAngleDegrees = 60.0
    var warningDepthDifferenceMeters = 0.10
    var rejectDepthDifferenceMeters = 0.15
    var distanceDeltaThresholdMeters = 0.15
    var maxReprojectionErrorPixels = 3.0
    var tagSizeSource = "auto-default"
    var showPoseAxes = false
    var showImperialHeight = true
    var levelFloorWithGravity = false
    var kalmanFilterEnabled = false
    var kalmanFilterSamples = 5
    static let allowedKalmanFilterSamples = [3, 5, 10, 20, 30]
    static let defaultsKey = "AprilFoolsAR.TagDebugSettings.v1"
    static let tagSizeEvidenceKey = "AprilFoolsAR.TagSizeEvidence.v1"

    private enum CodingKeys: String, CodingKey {
        case tagSizeMeters, tagSizeMode, competitionYear, maxDistanceMeters, maxPlaneAngleDegrees, warningDepthDifferenceMeters
        case rejectDepthDifferenceMeters, distanceDeltaThresholdMeters, maxReprojectionErrorPixels, tagSizeSource, showPoseAxes, showImperialHeight, levelFloorWithGravity
        case kalmanFilterEnabled, kalmanFilterSamples
    }
    init() {}
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tagSizeMeters = try values.decodeIfPresent(Double.self, forKey: .tagSizeMeters) ?? tagSizeMeters
        maxDistanceMeters = try values.decodeIfPresent(Double.self, forKey: .maxDistanceMeters) ?? maxDistanceMeters
        maxPlaneAngleDegrees = try values.decodeIfPresent(Double.self, forKey: .maxPlaneAngleDegrees) ?? maxPlaneAngleDegrees
        warningDepthDifferenceMeters = try values.decodeIfPresent(Double.self, forKey: .warningDepthDifferenceMeters) ?? warningDepthDifferenceMeters
        rejectDepthDifferenceMeters = try values.decodeIfPresent(Double.self, forKey: .rejectDepthDifferenceMeters) ?? rejectDepthDifferenceMeters
        distanceDeltaThresholdMeters = try values.decodeIfPresent(Double.self, forKey: .distanceDeltaThresholdMeters) ?? distanceDeltaThresholdMeters
        maxReprojectionErrorPixels = try values.decodeIfPresent(Double.self, forKey: .maxReprojectionErrorPixels) ?? maxReprojectionErrorPixels
        tagSizeSource = try values.decodeIfPresent(String.self, forKey: .tagSizeSource) ?? "frc-default"
        if let mode = try values.decodeIfPresent(String.self, forKey: .tagSizeMode) {
            tagSizeMode = mode
        } else if tagSizeSource == "frc-default", tagSizeMeters == Self.frcTagSizeMeters {
            // Upgrade the former unconfigured FRC default; retain operator-supplied widths.
            tagSizeMode = "auto"; tagSizeSource = "auto-default"
        } else {
            tagSizeMode = "custom"
        }
        competitionYear = try values.decodeIfPresent(Int.self, forKey: .competitionYear)
            ?? TagFieldCatalog.defaultYear(mode: tagSizeMode)
        showPoseAxes = try values.decodeIfPresent(Bool.self, forKey: .showPoseAxes) ?? false
        showImperialHeight = try values.decodeIfPresent(Bool.self, forKey: .showImperialHeight) ?? true
        levelFloorWithGravity = try values.decodeIfPresent(Bool.self, forKey: .levelFloorWithGravity) ?? false
        kalmanFilterEnabled = try values.decodeIfPresent(Bool.self, forKey: .kalmanFilterEnabled) ?? false
        kalmanFilterSamples = try values.decodeIfPresent(Int.self, forKey: .kalmanFilterSamples) ?? 5
    }

    var dictionary: [String: Any] {
        ["tagSizeMeters": tagSizeMeters, "tagSizeMode": tagSizeMode, "competitionYear": competitionYear, "maxDistanceMeters": maxDistanceMeters,
         "maxPlaneAngleDegrees": maxPlaneAngleDegrees, "warningDepthDifferenceMeters": warningDepthDifferenceMeters,
         "rejectDepthDifferenceMeters": rejectDepthDifferenceMeters, "distanceDeltaThresholdMeters": distanceDeltaThresholdMeters,
         "maxReprojectionErrorPixels": maxReprojectionErrorPixels,
         "tagSizeSource": tagSizeSource, "showPoseAxes": showPoseAxes, "showImperialHeight": showImperialHeight,
         "levelFloorWithGravity": levelFloorWithGravity,
         "kalmanFilterEnabled": kalmanFilterEnabled, "kalmanFilterSamples": kalmanFilterSamples]
    }
    func merging(_ changes: [String: Any]) throws -> TagDebugSettings {
        var result = self
        let requestedMode: String?
        if let value = changes["tagSizeMode"] {
            guard let mode = value as? String, ["auto", "ftc", "frc", "custom"].contains(mode) else {
                throw TagDebugError.invalid("Tag size mode must be auto, ftc, frc, or custom.")
            }
            requestedMode = mode
        } else { requestedMode = nil }
        let requestedYear: Int?
        if let value = changes["competitionYear"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                  (0...9999).contains(number.doubleValue) else {
                throw TagDebugError.invalid("Competition year must be a supported whole-number year, or 0 for Auto/custom.")
            }
            requestedYear = number.intValue
        } else { requestedYear = nil }
        for (key, value) in changes {
            if key == "tagSizeMode" || key == "competitionYear" { continue }
            if key == "showPoseAxes" || key == "showImperialHeight" || key == "levelFloorWithGravity" || key == "kalmanFilterEnabled" {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw TagDebugError.invalid("\(key) must be a boolean.")
                }
                if key == "showPoseAxes" { result.showPoseAxes = number.boolValue }
                else if key == "showImperialHeight" { result.showImperialHeight = number.boolValue }
                else if key == "levelFloorWithGravity" { result.levelFloorWithGravity = number.boolValue }
                else { result.kalmanFilterEnabled = number.boolValue }
                continue
            }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
                throw TagDebugError.invalid("\(key) must be a finite number.")
            }
            let value = number.doubleValue
            switch key {
            case "tagSizeMeters":
                if result.tagSizeMeters != value {
                    result.tagSizeSource = "manual"
                    result.tagSizeMode = "custom"
                    result.competitionYear = 0
                }
                result.tagSizeMeters = value
            case "maxDistanceMeters": result.maxDistanceMeters = value
            case "maxPlaneAngleDegrees": result.maxPlaneAngleDegrees = value
            case "warningDepthDifferenceMeters": result.warningDepthDifferenceMeters = value
            case "rejectDepthDifferenceMeters": result.rejectDepthDifferenceMeters = value
            case "distanceDeltaThresholdMeters": result.distanceDeltaThresholdMeters = value
            case "maxReprojectionErrorPixels": result.maxReprojectionErrorPixels = value
            case "kalmanFilterSamples":
                guard let samples = Self.allowedKalmanFilterSamples.first(where: { Double($0) == value }) else {
                    throw TagDebugError.invalid("Kalman smoothing samples must be 3, 5, 10, 20, or 30.")
                }
                result.kalmanFilterSamples = samples
            default: throw TagDebugError.invalid("Unknown debug setting: \(key)")
            }
        }
        if let mode = requestedMode {
            result.tagSizeMode = mode
            result.competitionYear = mode == tagSizeMode ? competitionYear : TagFieldCatalog.defaultYear(mode: mode)
            if mode == "custom", tagSizeMode != "custom" { result.tagSizeSource = "manual" }
        }
        if let year = requestedYear { result.competitionYear = year }
        if requestedMode != nil || requestedYear != nil {
            switch result.tagSizeMode {
            case "auto": result.tagSizeMeters = Self.frcTagSizeMeters; result.tagSizeSource = "auto-default"
            case "ftc", "frc":
                guard let width = TagFieldCatalog.referenceWidth(mode: result.tagSizeMode, year: result.competitionYear) else {
                    throw TagDebugError.invalid("Choose a supported competition year for the selected field type.")
                }
                result.tagSizeMeters = width; result.tagSizeSource = "\(result.tagSizeMode)-default"
            default: break
            }
        }
        guard (0.001...5).contains(result.tagSizeMeters), (0.05...50).contains(result.maxDistanceMeters),
              ["auto", "ftc", "frc", "custom"].contains(result.tagSizeMode),
              ((result.tagSizeMode == "custom" || result.tagSizeMode == "auto") ? result.competitionYear == 0 :
                TagFieldCatalog.referenceWidth(mode: result.tagSizeMode, year: result.competitionYear) == result.tagSizeMeters),
              (result.tagSizeMode != "auto" || result.tagSizeMeters == Self.frcTagSizeMeters),
              result.maxPlaneAngleDegrees > 0, result.maxPlaneAngleDegrees <= 90,
              result.warningDepthDifferenceMeters >= 0, result.rejectDepthDifferenceMeters > 0,
              result.warningDepthDifferenceMeters < result.rejectDepthDifferenceMeters, result.rejectDepthDifferenceMeters <= 10,
              (0...10).contains(result.distanceDeltaThresholdMeters),
              result.maxReprojectionErrorPixels > 0, result.maxReprojectionErrorPixels <= 100,
              Self.allowedKalmanFilterSamples.contains(result.kalmanFilterSamples) else {
            throw TagDebugError.invalid("Settings out of range: positive size/distance/error, plane angle 0–90°, 0 ≤ warning < reject depth difference, and distance delta threshold 0–10 m are required.")
        }
        return result
    }
    static func load(from defaults: UserDefaults = .standard) -> TagDebugSettings {
        guard let data = defaults.data(forKey: defaultsKey), let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        guard (try? saved.merging([:])) != nil else { return Self() }
        return saved
    }
    func persist(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
    /// Keep a recording's initial AR-width basis even when it was accepted before recording began.
    func matchingTagSizeEvidence(from defaults: UserDefaults = .standard) -> [String: Any]? {
        guard tagSizeSource == "ar-two-point-edge", let data = defaults.data(forKey: Self.tagSizeEvidenceKey),
              let evidence = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let width = TagDebugMath.number(evidence["measuredEdgeMeters"]),
              abs(width - tagSizeMeters) <= 1e-9,
              let points = evidence["sourcePoints"] as? [[String: Any]], points.count == 2 else { return nil }
        return evidence
    }
}

struct TagDepthSamples {
    var centerDepthMeters: Double?
    var rawCenterDepthMeters: Double?
    var centerConfidence: Int?
    var meanDepthMeters: Double?
    var validNeighborCount = 0
    var candidateNeighborCount = 0
    var depthPixel: [Int]?
    var reason = "Scene depth unavailable"
    var dictionary: [String: Any] {
        ["centerDepthMeters": centerDepthMeters as Any? ?? NSNull(), "rawCenterDepthMeters": rawCenterDepthMeters as Any? ?? NSNull(),
         "centerConfidence": centerConfidence as Any? ?? NSNull(), "meanDepthMeters": meanDepthMeters as Any? ?? NSNull(),
         "validNeighborCount": validNeighborCount, "candidateNeighborCount": candidateNeighborCount,
         "depthPixel": depthPixel as Any? ?? NSNull(), "reason": reason, "source": "sceneDepth", "neighborhood": "confidence-filtered 3x3 arithmetic mean"]
    }
}

enum TagDebugMath {
    /// A decoded family/ID contains no physical scale or competition identity.
    /// Compare independent same-frame optical LiDAR Z with a reference-size pose,
    /// then select a supported nominal width separately for every detection.
    static func resolveTagSize(_ detection: [String: Any], depth: TagDepthSamples,
                               settings: TagDebugSettings, tracking: String) -> [String: Any] {
        var result = detection
        if settings.tagSizeMode != "auto" {
            let explicitField = settings.tagSizeMode == "ftc" || settings.tagSizeMode == "frc"
            let tagID = number(detection["id"]).flatMap { value -> Int? in
                guard value >= 0, value <= 10000, value.rounded() == value else { return nil }; return Int(value)
            }
            guard let width = explicitField ? TagFieldCatalog.width(mode: settings.tagSizeMode, year: settings.competitionYear, tagID: tagID) : settings.tagSizeMeters else {
                result.removeValue(forKey: "pose")
                result["tagSizeResolution"] = ["status": "unavailable", "source": settings.tagSizeSource,
                    "fieldType": settings.tagSizeMode, "competitionYear": settings.competitionYear,
                    "tagSizeMeters": NSNull(), "label": TagFieldCatalog.label(mode: settings.tagSizeMode, year: settings.competitionYear),
                    "reason": "Tag ID is not in the selected season's size map; choose the matching field/year or a custom width in Settings."]
                return result
            }
            var explicit = AFSCSizeInput()
            explicit.selected_edge_m = coreOptional(width)
            explicit.reference_edge_m = number((detection["pose"] as? [String: Any])?["tagSizeMeters"]) ?? 0
            guard afsc_field_resolve_size(&explicit).selected != 0 else {
                result.removeValue(forKey: "pose"); return result
            }
            if let pose = detection["pose"] as? [String: Any] {
                if let scaled = rescaledPose(pose, width: width, source: settings.tagSizeSource) { result["pose"] = scaled }
                else { result.removeValue(forKey: "pose") }
            }
            let label = explicitField ? TagFieldCatalog.label(mode: settings.tagSizeMode, year: settings.competitionYear) :
                (settings.tagSizeSource == "ar-two-point-edge" ? "AR estimate" : "manual")
            result["tagSizeResolution"] = ["status": "selected", "source": settings.tagSizeSource,
                "fieldType": settings.tagSizeMode, "competitionYear": explicitField ? settings.competitionYear as Any : NSNull(),
                "tagSizeMeters": width, "label": label, "reason": explicitField ? "Operator-selected field type and competition year" : "Operator-selected tag width"]
            return result
        }
        var evidence: [String: Any] = ["status": "unavailable", "source": "sceneDepth-standard-match",
            "fieldType": "auto", "competitionYear": NSNull(),
            "label": "Auto", "tagSizeMeters": NSNull(), "relativeTolerance": 0.10,
            "centerDepthMeters": depth.centerDepthMeters.flatMap { $0.isFinite ? $0 : nil } as Any? ?? NSNull(),
            "centerConfidence": depth.centerConfidence as Any? ?? NSNull()]
        func unavailable(_ reason: String) -> [String: Any] {
            result.removeValue(forKey: "pose")
            evidence["reason"] = reason
            result["tagSizeResolution"] = evidence
            return result
        }
        var input = AFSCSizeInput()
        input.automatic = 1
        input.tracking_usable = tracking == "normal" ? 1 : 0
        let pose = detection["pose"] as? [String: Any] ?? [:]
        input.reference_edge_m = number(pose["tagSizeMeters"]) ?? 0
        input.pose = corePoseObservation(detection)
        input.depth = coreDepthObservation(depth: depth.centerDepthMeters, confidence: depth.centerConfidence.map(Double.init))
        input.settings = coreMeasurementSettings(settings)
        let standards = TagFieldCatalog.autoStandards.map {
            AFSCSizeStandard(edge_m: $0.edge, relative_tolerance: $0.tolerance)
        }
        let resolution = standards.withUnsafeBufferPointer { buffer -> AFSCSizeResolution in
            input.standards = buffer.baseAddress; input.standard_count = buffer.count
            return afsc_field_resolve_size(&input)
        }
        if let estimate = coreValue(resolution.estimated_edge_m) {
            evidence["estimatedEdgeMeters"] = estimate
            evidence["referenceTagSizeMeters"] = input.reference_edge_m
        }
        guard resolution.selected != 0, let width = coreValue(resolution.edge_m),
              let tolerance = coreValue(resolution.relative_tolerance),
              TagFieldCatalog.autoStandards.indices.contains(Int(resolution.standard_index)) else {
            switch resolution.reason {
            case AFSC_SIZE_TRACKING_UNAVAILABLE:
                return unavailable("Auto size needs normal AR tracking; choose a tag width in Settings.")
            case AFSC_SIZE_DEPTH_UNAVAILABLE:
                return unavailable("Auto size needs high-confidence LiDAR at the tag center; choose a tag width in Settings.")
            case AFSC_SIZE_POSE_UNAVAILABLE:
                return unavailable("Auto size needs a reliable, unambiguous tag pose; choose a tag width in Settings.")
            case AFSC_SIZE_NO_UNIQUE_MATCH:
                return unavailable("Tag width does not uniquely match a standard size; enter or measure it in Settings.")
            case AFSC_SIZE_TOO_FAR:
                return unavailable("Tag range exceeds the configured maximum for Auto size.")
            default:
                return unavailable("Physical tag width could not be estimated.")
            }
        }
        guard let scaled = rescaledPose(pose, width: width, source: "sceneDepth-standard-match") else {
            return unavailable("Tag range exceeds the configured maximum for Auto size.")
        }
        result["pose"] = scaled
        evidence["status"] = "selected"; evidence["tagSizeMeters"] = width
        evidence["label"] = TagFieldCatalog.autoStandards[Int(resolution.standard_index)].label
        evidence["relativeTolerance"] = tolerance
        evidence["reason"] = "Nominal width inferred from LiDAR; competition identity is not encoded by the tag."
        result["tagSizeResolution"] = evidence
        return result
    }

    private static func rescaledPose(_ pose: [String: Any], width: Double, source: String) -> [String: Any]? {
        guard let reference = number(pose["tagSizeMeters"]), reference > 0,
              let translation = numbers(pose["translation"], count: 3) else { return nil }
        var input = AFSCMetricPose()
        input.translation = coreVector(translation); input.reference_edge_m = reference
        input.pose_error_m2 = coreOptional(number(pose["poseError"]))
        input.second_pose_error_m2 = coreOptional(number(pose["secondPoseError"]))
        input.candidate_translation_separation_m = coreOptional(number(pose["candidateTranslationSeparationMeters"]))
        let scaled = afsc_field_rescale_metric_pose(&input, width)
        guard scaled.available != 0 else { return nil }
        var result = pose
        result["translation"] = [scaled.translation.x, scaled.translation.y, scaled.translation.z]
        result["rangeMeters"] = scaled.range_m
        for (key, value) in [("poseError", scaled.pose_error_m2), ("secondPoseError", scaled.second_pose_error_m2),
                             ("candidateTranslationSeparationMeters", scaled.candidate_translation_separation_m)] {
            if let metric = coreValue(value) { result[key] = metric }
        }
        result["tagSizeMeters"] = scaled.edge_m; result["tagSizeSource"] = source
        return result
    }

    static func measuredTagSize(points: [[String: Any]], worldDistance: Double?, segmentID: String, tracking: String, frameAgeSeconds: Double) throws -> Double {
        let pointsUsable = points.allSatisfy {
            ($0["segmentId"] as? String) == segmentID && ($0["source"] as? String) == "sceneDepth"
                && [1, 2].contains(($0["confidence"] as? NSNumber)?.intValue ?? -1)
        }
        guard afsc_measured_tag_size(points.count == 2 ? 2 : 0, tracking == "normal" ? 1 : 0,
                                     pointsUsable ? 1 : 0, frameAgeSeconds, coreOptional(worldDistance)) != 0,
              let distance = worldDistance else {
            throw TagDebugError.invalid("Measure one tag edge with two valid LiDAR points in the current segment (normal tracking, confidence 1/2, width 10 mm–2 m).")
        }
        return distance
    }
    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }; return number.doubleValue
    }
    static func numbers(_ value: Any?, count: Int) -> [Double]? {
        guard let values = value as? [NSNumber], values.count == count else { return nil }
        let result = values.map(\.doubleValue); return result.allSatisfy(\.isFinite) ? result : nil
    }
    /// Samples the exact captured frame. A neighboring valid depth never substitutes for an invalid center.
    static func sampleDepth(depth: CVPixelBuffer?, confidence: CVPixelBuffer?, center: [Double], imageWidth: Int, imageHeight: Int) -> TagDepthSamples {
        var result = TagDepthSamples()
        guard let depth, center.count == 2, center.allSatisfy(\.isFinite), imageWidth > 0, imageHeight > 0,
              CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32 else { return result }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        let nx = center[0] / Double(imageWidth), ny = center[1] / Double(imageHeight)
        guard width > 0, height > 0, nx >= 0, nx < 1, ny >= 0, ny < 1 else { result.reason = "Tag center outside depth image"; return result }
        let x = Int(nx * Double(width)), y = Int(ny * Double(height)); result.depthPixel = [x, y]
        guard CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else { result.reason = "Depth buffer lock failed"; return result }
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depth), CVPixelBufferGetBytesPerRow(depth) >= width * 4 else { return result }
        func depthValue(_ x: Int, _ y: Int) -> Double? {
            let value = Double(depthBase.advanced(by: y * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)[x])
            return value.isFinite && value > 0 ? value : nil
        }
        result.rawCenterDepthMeters = depthValue(x, y)
        guard let confidence, CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 else { result.reason = "Matching confidence map unavailable"; return result }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { result.reason = "Confidence buffer lock failed"; return result }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let confidenceBase = CVPixelBufferGetBaseAddress(confidence), CVPixelBufferGetBytesPerRow(confidence) >= width else { return result }
        func confidenceValue(_ x: Int, _ y: Int) -> Int { Int(confidenceBase.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)[x]) }
        let c = confidenceValue(x, y); result.centerConfidence = c
        if c == 1 || c == 2 { result.centerDepthMeters = result.rawCenterDepthMeters }
        var values = [Double]()
        for yy in max(0, y-1)...min(height-1, y+1) { for xx in max(0, x-1)...min(width-1, x+1) {
            result.candidateNeighborCount += 1
            let c = confidenceValue(xx, yy)
            if (c == 1 || c == 2), let value = depthValue(xx, yy) { values.append(value) }
        } }
        result.validNeighborCount = values.count
        if !values.isEmpty { result.meanDepthMeters = values.reduce(0, +) / Double(values.count) }
        result.reason = result.centerDepthMeters != nil ? "Accepted center confidence \(c)" : (c == 0 ? "Center confidence 0 rejected" : "Center depth invalid")
        return result
    }

    static func enrich(_ detection: [String: Any], depth: TagDepthSamples, settings: TagDebugSettings, tracking: String) -> [String: Any] {
        var result = detection
        let pose = detection["pose"] as? [String: Any]
        let translation = numbers(pose?["translation"], count: 3)
        let euler = numbers(pose?["eulerDegrees"], count: 3)
        let range = number(pose?["rangeMeters"]), plane = number(pose?["planeAngleDegrees"])
        let bearing = number(pose?["opticalAxisAngleDegrees"]), reprojection = number(pose?["reprojectionRMSEPixels"])
        let poseZ = translation?[2], margin = number(detection["decisionMargin"]), hamming = number(detection["hamming"])
        var corePose = corePoseObservation(detection)
        var coreDepth = coreDepthObservation(depth: depth.centerDepthMeters, confidence: depth.centerConfidence.map(Double.init))
        var coreSettings = coreMeasurementSettings(settings)
        let quality = afsc_pose_quality(&corePose, &coreDepth, &coreSettings, tracking == "normal" ? 1 : 0)
        let acceptedDepth = coreValue(quality.accepted_depth_z_m)
        let delta = coreValue(quality.depth_difference_m)
        let status: String, reason: String
        switch quality.reason {
        case AFSC_QUALITY_TRACKING_LIMITED: status = "trackingLimited"; reason = "AR tracking must be normal"
        case AFSC_QUALITY_POSE_UNAVAILABLE: status = "poseUnavailable"; reason = "Valid camera-relative pose/quality unavailable"
        case AFSC_QUALITY_AMBIGUOUS: status = "ambiguous"; reason = "Distinct alternative planar pose"
        case AFSC_QUALITY_TOO_FAR: status = "tooFar"; reason = "Camera-to-tag range exceeds configured maximum"
        case AFSC_QUALITY_BAD_ANGLE: status = "badAngle"; reason = "Tag plane incidence exceeds configured maximum"
        case AFSC_QUALITY_LOW_CONFIDENCE_POSE: status = "lowConfidence"; reason = "Conservative quality gate: reprojection, positive decision margin, and zero corrected bits required"
        case AFSC_QUALITY_LOW_CONFIDENCE_DEPTH: status = "lowConfidence"; reason = "LiDAR center confidence 0 rejected"
        case AFSC_QUALITY_MISSING_DEPTH: status = "missingDepth"; reason = depth.reason
        case AFSC_QUALITY_DEPTH_REJECTED: status = "depthMismatch"; reason = "Absolute center LiDAR − optical pose Z exceeds reject threshold"
        case AFSC_QUALITY_DEPTH_WARNING: status = "depthMismatch"; reason = "Check depth: above warning threshold"
        default: status = "valid"; reason = "Current camera-relative checks pass; absolute field accuracy is not certified"
        }
        let severity = coreSeverity(quality.severity)
        let reasons = [reason]
        var debug: [String: Any] = ["id": detection["id"] as Any? ?? NSNull(), "status": status, "severity": severity, "valid": status == "valid",
            "reasons": reasons, "translationMeters": translation as Any? ?? NSNull(), "eulerDegrees": euler as Any? ?? NSNull(),
            "opticalPoseZMeters": poseZ as Any? ?? NSNull(), "rangeMeters": range as Any? ?? NSNull(),
            "planeAngleDegrees": plane as Any? ?? NSNull(), "centerBearingDegrees": bearing as Any? ?? NSNull(),
            "reprojectionRMSEPixels": reprojection as Any? ?? NSNull(), "decisionMargin": margin as Any? ?? NSNull(), "hamming": hamming as Any? ?? NSNull(),
            "centerDepthMeters": acceptedDepth as Any? ?? NSNull(), "rawCenterDepthMeters": depth.rawCenterDepthMeters.flatMap { $0.isFinite ? $0 : nil } as Any? ?? NSNull(),
            "meanDepthMeters": depth.meanDepthMeters as Any? ?? NSNull(), "centerConfidence": depth.centerConfidence as Any? ?? NSNull(),
            "validNeighborCount": depth.validNeighborCount, "depthDifferenceMeters": delta as Any? ?? NSNull(), "tracking": tracking,
            "angleConvention": "plane incidence normal-to-view; center bearing optical-axis offset", "coordinates": "camera optical +X right +Y down +Z forward"]
        debug["tagSizeMeters"] = number(pose?["tagSizeMeters"]) as Any? ?? NSNull()
        debug["tagSizeSource"] = pose?["tagSizeSource"] as Any? ?? settings.tagSizeSource
        if let resolution = detection["tagSizeResolution"] as? [String: Any] {
            debug["tagSizeResolution"] = resolution
            if resolution["status"] as? String == "unavailable" {
                debug["status"] = "sizeUnavailable"; debug["valid"] = false
                debug["reasons"] = [resolution["reason"] as? String ?? "Choose a tag width in Settings."]
            }
        }
        result["depth"] = depth.dictionary; result["debug"] = debug
        return result
    }

    // C ABI adapters keep platform parsing, units, and ARKit axes at the boundary.
    static func coreOptional(_ value: Double?) -> AFSCOptionalDouble {
        guard let value else { return AFSCOptionalDouble() }
        return AFSCOptionalDouble(available: 1, value: value)
    }
    static func coreValue(_ value: AFSCOptionalDouble) -> Double? { value.available != 0 ? value.value : nil }
    static func coreVector(_ values: [Double]) -> AFSCVec3 {
        AFSCVec3(x: values[0], y: values[1], z: values[2])
    }
    static func corePoseObservation(_ detection: [String: Any]) -> AFSCPoseObservation {
        let pose = detection["pose"] as? [String: Any]
        var result = AFSCPoseObservation()
        if let translation = numbers(pose?["translation"], count: 3) {
            result.translation_available = 1; result.translation = coreVector(translation)
        }
        result.orientation_available = numbers(pose?["eulerDegrees"], count: 3) == nil ? 0 : 1
        result.range_m = coreOptional(number(pose?["rangeMeters"]))
        result.plane_angle_rad = coreOptional(number(pose?["planeAngleDegrees"]).map { $0 * .pi / 180 })
        result.bearing_rad = coreOptional(number(pose?["opticalAxisAngleDegrees"]).map { $0 * .pi / 180 })
        result.reprojection_rms_px = coreOptional(number(pose?["reprojectionRMSEPixels"]))
        result.decision_margin = coreOptional(number(detection["decisionMargin"]))
        result.corrected_bits = coreOptional(number(detection["hamming"]))
        result.ambiguous = (pose?["ambiguous"] as? Bool).map { $0 ? 1 : 0 } ?? -1
        return result
    }
    static func coreDepthObservation(depth: Double?, confidence: Double?) -> AFSCDepthObservation {
        AFSCDepthObservation(center_z_m: coreOptional(depth), confidence: coreOptional(confidence))
    }
    static func coreMeasurementSettings(_ settings: TagDebugSettings) -> AFSCMeasurementSettings {
        AFSCMeasurementSettings(max_range_m: settings.maxDistanceMeters,
            max_plane_angle_rad: settings.maxPlaneAngleDegrees * .pi / 180,
            max_reprojection_rms_px: settings.maxReprojectionErrorPixels,
            warning_depth_difference_m: settings.warningDepthDifferenceMeters,
            reject_depth_difference_m: settings.rejectDepthDifferenceMeters)
    }
    static func coreIntrinsics(_ matrix: simd_float3x3) -> AFSCIntrinsics {
        var result = AFSCIntrinsics()
        withUnsafeMutableBytes(of: &result.values) { bytes in
            let values = bytes.bindMemory(to: Double.self)
            for column in 0..<3 { for row in 0..<3 { values[column*3+row] = Double(matrix[column][row]) } }
        }
        return result
    }
    static func coreWorldFromOptical(_ cameraToWorld: simd_float4x4) -> AFSCMat4 {
        var result = AFSCMat4()
        withUnsafeMutableBytes(of: &result.values) { bytes in
            let values = bytes.bindMemory(to: Double.self)
            for column in 0..<4 { for row in 0..<4 {
                // Native ARKit is +Y up / -Z forward; the portable core is optical.
                values[column*4+row] = Double(cameraToWorld[column][row]) * (column == 1 || column == 2 ? -1 : 1)
            } }
        }
        return result
    }
    static func coreSeverity(_ severity: AFSCSeverity) -> String {
        switch severity {
        case AFSC_SEVERITY_NEUTRAL: return "neutral"
        case AFSC_SEVERITY_WARNING: return "warning"
        case AFSC_SEVERITY_BAD: return "bad"
        default: return "good"
        }
    }

}
