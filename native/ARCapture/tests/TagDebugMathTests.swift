import XCTest
import CoreVideo

final class TagDebugMathTests: XCTestCase {
    private func row(poseChanges: [String: Any] = [:], changes: [String: Any] = [:]) -> [String: Any] {
        var pose: [String: Any] = ["translation": [3.0, 4.0, 5.0], "eulerDegrees": [0.0, 0.0, 0.0],
            "rangeMeters": sqrt(50.0), "planeAngleDegrees": 20.0, "opticalAxisAngleDegrees": 45.0,
            "reprojectionRMSEPixels": 0.2, "ambiguous": false]
        poseChanges.forEach { pose[$0.key] = $0.value }
        var value: [String: Any] = ["id": 42, "family": "tag36h11", "pose": pose, "decisionMargin": 100.0, "hamming": 0]
        changes.forEach { value[$0.key] = $0.value }
        return value
    }
    private var settings: TagDebugSettings { var value = TagDebugSettings(); value.maxDistanceMeters = 10; return value }
    private func depth(_ z: Double? = 5, confidence: Int? = 2, mean: Double? = 5) -> TagDepthSamples {
        var value = TagDepthSamples(); value.centerDepthMeters = z; value.rawCenterDepthMeters = z
        value.centerConfidence = confidence; value.meanDepthMeters = mean; value.validNeighborCount = 9; return value
    }
    private func debug(_ row: [String: Any]? = nil, depth: TagDepthSamples? = nil, tracking: String = "normal", settings: TagDebugSettings? = nil) -> [String: Any] {
        TagDebugMath.enrich(row ?? self.row(), depth: depth ?? self.depth(), settings: settings ?? self.settings, tracking: tracking)["debug"] as! [String: Any]
    }
    func testOpticalZComparisonDoesNotUseOffAxisEuclideanRange() {
        let result = debug()
        XCTAssertEqual(result["valid"] as? Bool, true)
        XCTAssertEqual(result["depthDifferenceMeters"] as? Double, 0)
        XCTAssertEqual(result["rangeMeters"] as? Double, sqrt(50))
        XCTAssertEqual(result["opticalPoseZMeters"] as? Double, 5)
        XCTAssertEqual(result["planeAngleDegrees"] as? Double, 20)
        XCTAssertEqual(result["centerBearingDegrees"] as? Double, 45)
    }
    func testExactDepthWarningRejectBoundariesAndAbsoluteDifference() {
        XCTAssertEqual(debug(depth: depth(5.1))["severity"] as? String, "good")
        XCTAssertEqual(debug(depth: depth(5.15))["severity"] as? String, "warning")
        XCTAssertEqual(debug(depth: depth(5.151))["severity"] as? String, "bad")
        XCTAssertEqual(debug(depth: depth(4.899))["severity"] as? String, "warning")
        XCTAssertEqual(debug(depth: depth(5.101))["valid"] as? Bool, false)
    }
    func testMissingWeakUnknownOrNonfiniteCenterNeverUsesNeighborhoodAsSubstitute() {
        for input in [depth(nil, confidence: 2, mean: 5), depth(5, confidence: nil, mean: 5), depth(5, confidence: 0, mean: 5), depth(5, confidence: 3, mean: 5), depth(.nan, confidence: 2, mean: 5)] {
            let result = debug(depth: input)
            XCTAssertEqual(result["valid"] as? Bool, false)
            XCTAssertTrue(result["depthDifferenceMeters"] is NSNull)
            XCTAssertNotEqual(result["severity"] as? String, "good")
        }
    }
    func testTrackingAmbiguityReprojectionAndCorrectedBitGates() {
        XCTAssertEqual(debug(tracking: "limited")["status"] as? String, "trackingLimited")
        XCTAssertEqual(debug(row(poseChanges: ["ambiguous": true]))["status"] as? String, "ambiguous")
        XCTAssertEqual(debug(row(poseChanges: ["reprojectionRMSEPixels": 3.01]))["status"] as? String, "lowConfidence")
        XCTAssertEqual(debug(row(poseChanges: ["reprojectionRMSEPixels": 3.0]))["valid"] as? Bool, true)
        XCTAssertEqual(debug(row(changes: ["hamming": 1]))["status"] as? String, "lowConfidence")
        XCTAssertEqual(debug(row(changes: ["decisionMargin": 0]))["status"] as? String, "lowConfidence")
        XCTAssertEqual(debug(row(poseChanges: ["planeAngleDegrees": 61]))["status"] as? String, "badAngle")
        XCTAssertEqual(debug(settings: TagDebugSettings())["status"] as? String, "tooFar")
        var missing = row(); missing.removeValue(forKey: "pose")
        XCTAssertEqual(debug(missing)["status"] as? String, "poseUnavailable")
    }
    func testSettingsValidationPersistenceAndSizeSource() throws {
        let defaults = UserDefaults(suiteName: "TagDebugMathTests.\(UUID().uuidString)")!
        let initial = TagDebugSettings()
        XCTAssertEqual(initial.tagSizeMeters, 0.1651)
        var ar = initial; ar.tagSizeSource = "ar-two-point-edge"
        let sameSize = try ar.merging(["tagSizeMeters": 0.1651, "maxDistanceMeters": 6])
        XCTAssertEqual(sameSize.tagSizeSource, "ar-two-point-edge")
        let manual = try ar.merging(["tagSizeMeters": 0.16]); XCTAssertEqual(manual.tagSizeSource, "manual")
        manual.persist(to: defaults); XCTAssertEqual(TagDebugSettings.load(from: defaults), manual)
        let invalidChanges: [[String: Any]] = [["tagSizeMeters": 0], ["maxDistanceMeters": -1], ["maxPlaneAngleDegrees": 91], ["tagSizeMeters": Double.nan], ["warningDepthDifferenceMeters": 0.15], ["maxReprojectionErrorPixels": 0], ["unknown": 1], ["tagSizeMeters": true]]
        for changes in invalidChanges {
            XCTAssertThrowsError(try initial.merging(changes))
        }
        XCTAssertEqual(initial.tagSizeMeters, 0.1651)
    }
    func testRecordingEvidenceRequiresMatchingARWidthSourceAndValue() throws {
        let defaults = UserDefaults(suiteName: "TagSizeEvidenceTests.\(UUID().uuidString)")!
        let evidence: [String: Any] = ["sourcePoints": [["frameId": "a"], ["frameId": "b"]], "measuredEdgeMeters": 0.1651, "method": "sceneDepth endpoints"]
        defaults.set(try JSONSerialization.data(withJSONObject: evidence), forKey: TagDebugSettings.tagSizeEvidenceKey)
        var ar = TagDebugSettings(); ar.tagSizeSource = "ar-two-point-edge"
        XCTAssertEqual(ar.matchingTagSizeEvidence(from: defaults)?["measuredEdgeMeters"] as? Double, 0.1651)
        ar.tagSizeMeters = 0.17; XCTAssertNil(ar.matchingTagSizeEvidence(from: defaults))
        ar.tagSizeMeters = 0.1651; ar.tagSizeSource = "manual"; XCTAssertNil(ar.matchingTagSizeEvidence(from: defaults))
    }
    func testPoseAxesPreferencePreservesLegacyWidthAndRequiresBoolean() throws {
        let defaults = UserDefaults(suiteName: "TagAxesSettingsTests.\(UUID().uuidString)")!
        var legacy = TagDebugSettings().dictionary
        legacy.removeValue(forKey: "showPoseAxes")
        legacy["tagSizeMeters"] = 0.1723456789
        legacy["tagSizeSource"] = "ar-two-point-edge"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: TagDebugSettings.defaultsKey)
        let loaded = TagDebugSettings.load(from: defaults)
        XCTAssertFalse(loaded.showPoseAxes)
        XCTAssertEqual(loaded.tagSizeMeters, 0.1723456789)
        let enabled = try loaded.merging(["showPoseAxes": true])
        XCTAssertTrue(enabled.showPoseAxes)
        XCTAssertEqual(enabled.tagSizeSource, "ar-two-point-edge")
        enabled.persist(to: defaults)
        XCTAssertEqual(TagDebugSettings.load(from: defaults), enabled)
        XCTAssertFalse(try enabled.merging(["showPoseAxes": false]).showPoseAxes)
        XCTAssertThrowsError(try enabled.merging(["showPoseAxes": 1]))
        XCTAssertThrowsError(try enabled.merging(["showPoseAxes": "true"]))
    }
    func testEnglishHeightPreferenceMigratesOnAndPersistsWithoutRoundingMeasuredWidth() throws {
        let suite = "HeightUnitsSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = TagDebugSettings().dictionary
        legacy.removeValue(forKey: "showImperialHeight")
        legacy["tagSizeMeters"] = 0.1723456789
        legacy["tagSizeSource"] = "ar-two-point-edge"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: TagDebugSettings.defaultsKey)
        let loaded = TagDebugSettings.load(from: defaults)
        XCTAssertTrue(loaded.showImperialHeight)
        let metricOnly = try loaded.merging(["showImperialHeight": false])
        XCTAssertFalse(metricOnly.showImperialHeight)
        XCTAssertEqual(metricOnly.tagSizeMeters, 0.1723456789)
        XCTAssertEqual(metricOnly.tagSizeSource, "ar-two-point-edge")
        metricOnly.persist(to: defaults)
        XCTAssertEqual(TagDebugSettings.load(from: defaults), metricOnly)
        XCTAssertTrue(try metricOnly.merging(["showImperialHeight": true]).showImperialHeight)
        XCTAssertThrowsError(try loaded.merging(["showImperialHeight": 1]))
        XCTAssertThrowsError(try loaded.merging(["showImperialHeight": "false"]))
    }
    func testMeasuredWidthUsesReviewedEndpointDistanceAndRejectsInvalidInputs() throws {
        let points: [[String: Any]] = [["source": "sceneDepth", "segmentId": "segment", "confidence": 2, "frameId": "a"], ["source": "sceneDepth", "segmentId": "segment", "confidence": 1, "frameId": "b"]]
        XCTAssertEqual(try TagDebugMath.measuredTagSize(points: points, worldDistance: 0.1651, segmentID: "segment", tracking: "normal", frameAgeSeconds: 0.01), 0.1651)
        XCTAssertThrowsError(try TagDebugMath.measuredTagSize(points: points, worldDistance: 0.1651, segmentID: "other", tracking: "normal", frameAgeSeconds: 0.01))
        XCTAssertThrowsError(try TagDebugMath.measuredTagSize(points: points, worldDistance: .nan, segmentID: "segment", tracking: "normal", frameAgeSeconds: 0.01))
        XCTAssertThrowsError(try TagDebugMath.measuredTagSize(points: points, worldDistance: 7, segmentID: "segment", tracking: "normal", frameAgeSeconds: 0.01))
        XCTAssertThrowsError(try TagDebugMath.measuredTagSize(points: points, worldDistance: 0.1651, segmentID: "segment", tracking: "limited", frameAgeSeconds: 0.01))
        XCTAssertThrowsError(try TagDebugMath.measuredTagSize(points: points, worldDistance: 0.1651, segmentID: "segment", tracking: "normal", frameAgeSeconds: 0.51))
    }
    private func buffer(_ format: OSType) -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 5, 5, format, [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary, &result), kCVReturnSuccess)
        return result!
    }
    func testSameFrameNormalizedMappingPaddedRowsAndFiltered3x3Mean() {
        let depth = buffer(kCVPixelFormatType_DepthFloat32), confidence = buffer(kCVPixelFormatType_OneComponent8)
        CVPixelBufferLockBaseAddress(depth, []); CVPixelBufferLockBaseAddress(confidence, [])
        let d = CVPixelBufferGetBaseAddress(depth)!, c = CVPixelBufferGetBaseAddress(confidence)!
        memset(d, 0, CVPixelBufferGetBytesPerRow(depth)*5); memset(c, 0, CVPixelBufferGetBytesPerRow(confidence)*5)
        let values: [Float] = [4, 5, 6, 7, 5, 8, 9, 10, 11], confidences: [UInt8] = [2, 0, 1, 2, 2, 0, 2, 1, 0]
        for y in 1...3 { for x in 1...3 {
            let i = (y-1)*3+x-1
            d.advanced(by: y*CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)[x] = values[i]
            c.advanced(by: y*CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)[x] = confidences[i]
        } }
        CVPixelBufferUnlockBaseAddress(confidence, []); CVPixelBufferUnlockBaseAddress(depth, [])
        let samples = TagDebugMath.sampleDepth(depth: depth, confidence: confidence, center: [300, 200], imageWidth: 600, imageHeight: 400)
        XCTAssertEqual(samples.depthPixel!, [2, 2]); XCTAssertEqual(samples.centerDepthMeters, 5)
        XCTAssertEqual(samples.centerConfidence, 2); XCTAssertEqual(samples.validNeighborCount, 6)
        XCTAssertEqual(samples.meanDepthMeters!, 41.0/6.0, accuracy: 1e-8)
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(depth), 5*4)
        let missing = TagDebugMath.sampleDepth(depth: depth, confidence: nil, center: [300, 200], imageWidth: 600, imageHeight: 400)
        XCTAssertEqual(missing.rawCenterDepthMeters, 5); XCTAssertNil(missing.centerDepthMeters); XCTAssertNil(missing.meanDepthMeters)
    }
}
