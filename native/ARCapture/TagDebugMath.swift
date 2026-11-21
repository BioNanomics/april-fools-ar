import Foundation
import CoreVideo
import CoreFoundation

enum TagDebugError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

struct TagDebugSettings: Codable, Equatable {
    var tagSizeMeters = 0.1651
    var maxDistanceMeters = 5.0
    var maxPlaneAngleDegrees = 60.0
    var warningDepthDifferenceMeters = 0.10
    var rejectDepthDifferenceMeters = 0.15
    var maxReprojectionErrorPixels = 3.0
    var tagSizeSource = "frc-default"
    var showPoseAxes = false
    static let defaultsKey = "AprilFoolsAR.TagDebugSettings.v1"
    static let tagSizeEvidenceKey = "AprilFoolsAR.TagSizeEvidence.v1"

    private enum CodingKeys: String, CodingKey {
        case tagSizeMeters, maxDistanceMeters, maxPlaneAngleDegrees, warningDepthDifferenceMeters
        case rejectDepthDifferenceMeters, maxReprojectionErrorPixels, tagSizeSource, showPoseAxes
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
        maxReprojectionErrorPixels = try values.decodeIfPresent(Double.self, forKey: .maxReprojectionErrorPixels) ?? maxReprojectionErrorPixels
        tagSizeSource = try values.decodeIfPresent(String.self, forKey: .tagSizeSource) ?? tagSizeSource
        showPoseAxes = try values.decodeIfPresent(Bool.self, forKey: .showPoseAxes) ?? false
    }

    var dictionary: [String: Any] {
        ["tagSizeMeters": tagSizeMeters, "maxDistanceMeters": maxDistanceMeters,
         "maxPlaneAngleDegrees": maxPlaneAngleDegrees, "warningDepthDifferenceMeters": warningDepthDifferenceMeters,
         "rejectDepthDifferenceMeters": rejectDepthDifferenceMeters, "maxReprojectionErrorPixels": maxReprojectionErrorPixels,
         "tagSizeSource": tagSizeSource, "showPoseAxes": showPoseAxes]
    }
    func merging(_ changes: [String: Any]) throws -> TagDebugSettings {
        var result = self
        for (key, value) in changes {
            if key == "showPoseAxes" {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw TagDebugError.invalid("showPoseAxes must be a boolean.")
                }
                result.showPoseAxes = number.boolValue
                continue
            }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
                throw TagDebugError.invalid("\(key) must be a finite number.")
            }
            let value = number.doubleValue
            switch key {
            case "tagSizeMeters":
                if result.tagSizeMeters != value { result.tagSizeSource = "manual" }
                result.tagSizeMeters = value
            case "maxDistanceMeters": result.maxDistanceMeters = value
            case "maxPlaneAngleDegrees": result.maxPlaneAngleDegrees = value
            case "warningDepthDifferenceMeters": result.warningDepthDifferenceMeters = value
            case "rejectDepthDifferenceMeters": result.rejectDepthDifferenceMeters = value
            case "maxReprojectionErrorPixels": result.maxReprojectionErrorPixels = value
            default: throw TagDebugError.invalid("Unknown debug setting: \(key)")
            }
        }
        guard (0.001...5).contains(result.tagSizeMeters), (0.05...50).contains(result.maxDistanceMeters),
              result.maxPlaneAngleDegrees > 0, result.maxPlaneAngleDegrees <= 90,
              result.warningDepthDifferenceMeters >= 0, result.rejectDepthDifferenceMeters > 0,
              result.warningDepthDifferenceMeters < result.rejectDepthDifferenceMeters, result.rejectDepthDifferenceMeters <= 10,
              result.maxReprojectionErrorPixels > 0, result.maxReprojectionErrorPixels <= 100 else {
            throw TagDebugError.invalid("Settings out of range: positive size/distance/error, plane angle 0–90°, and 0 ≤ warning < reject depth difference are required.")
        }
        return result
    }
    static func load(from defaults: UserDefaults = .standard) -> TagDebugSettings {
        guard let data = defaults.data(forKey: defaultsKey), let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var numbers = saved.dictionary; numbers.removeValue(forKey: "tagSizeSource")
        guard (try? Self().merging(numbers)) != nil else { return Self() }
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
    static func measuredTagSize(points: [[String: Any]], worldDistance: Double?, segmentID: String, tracking: String, frameAgeSeconds: Double) throws -> Double {
        guard points.count == 2, tracking == "normal", frameAgeSeconds >= 0, frameAgeSeconds <= 0.5,
              points.allSatisfy({ ($0["segmentId"] as? String) == segmentID && ($0["source"] as? String) == "sceneDepth" && [1, 2].contains(($0["confidence"] as? NSNumber)?.intValue ?? -1) }),
              let distance = worldDistance, distance.isFinite, (0.01...2).contains(distance) else {
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
        let acceptedDepth = depth.centerDepthMeters.flatMap { $0.isFinite && $0 > 0 && [1, 2].contains(depth.centerConfidence ?? -1) ? $0 : nil }
        let delta = poseZ.flatMap { z in acceptedDepth.map { abs($0 - z) } }
        var status = "valid", severity = "good", reasons = [String]()
        func set(_ code: String, _ level: String, _ reason: String) { status = code; severity = level; reasons.append(reason) }
        if tracking != "normal" { set("trackingLimited", "neutral", "AR tracking must be normal") }
        else if poseZ == nil || poseZ! <= 0 || range == nil || plane == nil || bearing == nil || reprojection == nil || translation == nil || euler == nil { set("poseUnavailable", "neutral", "Valid camera-relative pose/quality unavailable") }
        else if pose?["ambiguous"] as? Bool == true { set("ambiguous", "warning", "Distinct alternative planar pose") }
        else if range! > settings.maxDistanceMeters { set("tooFar", "bad", "Camera-to-tag range exceeds configured maximum") }
        else if plane! > settings.maxPlaneAngleDegrees { set("badAngle", "bad", "Tag plane incidence exceeds configured maximum") }
        else if reprojection! > settings.maxReprojectionErrorPixels || hamming == nil || hamming! > 0 || margin == nil || margin! <= 0 {
            set("lowConfidence", "warning", "Conservative quality gate: reprojection, positive decision margin, and zero corrected bits required")
        }
        else if depth.centerConfidence == 0 { set("lowConfidence", "neutral", "LiDAR center confidence 0 rejected") }
        else if acceptedDepth == nil { set("missingDepth", "neutral", depth.reason) }
        else if delta! > settings.rejectDepthDifferenceMeters + 1e-9 { set("depthMismatch", "bad", "Absolute center LiDAR − optical pose Z exceeds reject threshold") }
        else if delta! > settings.warningDepthDifferenceMeters + 1e-9 { set("depthMismatch", "warning", "Check depth: above warning threshold") }
        else { reasons.append("Current camera-relative checks pass; absolute field accuracy is not certified") }
        let debug: [String: Any] = ["id": detection["id"] as Any? ?? NSNull(), "status": status, "severity": severity, "valid": status == "valid",
            "reasons": reasons, "translationMeters": translation as Any? ?? NSNull(), "eulerDegrees": euler as Any? ?? NSNull(),
            "opticalPoseZMeters": poseZ as Any? ?? NSNull(), "rangeMeters": range as Any? ?? NSNull(),
            "planeAngleDegrees": plane as Any? ?? NSNull(), "centerBearingDegrees": bearing as Any? ?? NSNull(),
            "reprojectionRMSEPixels": reprojection as Any? ?? NSNull(), "decisionMargin": margin as Any? ?? NSNull(), "hamming": hamming as Any? ?? NSNull(),
            "centerDepthMeters": acceptedDepth as Any? ?? NSNull(), "rawCenterDepthMeters": depth.rawCenterDepthMeters.flatMap { $0.isFinite ? $0 : nil } as Any? ?? NSNull(),
            "meanDepthMeters": depth.meanDepthMeters as Any? ?? NSNull(), "centerConfidence": depth.centerConfidence as Any? ?? NSNull(),
            "validNeighborCount": depth.validNeighborCount, "depthDifferenceMeters": delta as Any? ?? NSNull(), "tracking": tracking,
            "angleConvention": "plane incidence normal-to-view; center bearing optical-axis offset", "coordinates": "camera optical +X right +Y down +Z forward"]
        result["depth"] = depth.dictionary; result["debug"] = debug
        return result
    }
}
