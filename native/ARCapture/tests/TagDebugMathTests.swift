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
    private func sizedRow(poseChanges: [String: Any] = [:], changes: [String: Any] = [:]) -> [String: Any] {
        var pose: [String: Any] = ["tagSizeMeters": 0.1651, "rotationRowMajor": [1.0, 0, 0, 0, 1, 0, 0, 0, 1],
            "poseError": 0.02, "secondPoseError": 0.05, "secondReprojectionRMSEPixels": 0.4,
            "poseErrorRatio": 0.4, "candidateTranslationSeparationMeters": 0.01,
            "candidateRotationSeparationDegrees": 2.0]
        poseChanges.forEach { pose[$0.key] = $0.value }
        return row(poseChanges: pose, changes: changes)
    }
    private func resolve(_ input: [String: Any]? = nil, depth samples: TagDepthSamples? = nil,
                         settings configured: TagDebugSettings? = nil, tracking: String = "normal") -> [String: Any] {
        TagDebugMath.resolveTagSize(input ?? sizedRow(), depth: samples ?? depth(), settings: configured ?? settings, tracking: tracking)
    }
    func testAutomaticSizesUseIndependentOpticalDepthForEachTagRegardlessOfID() throws {
        // An identical decoded ID can be printed at any size. The off-axis range is not the optical Z used here.
        for width in [0.0508, 0.08255, 0.1016, 0.127, 0.1524, 0.1651] {
            let scale = width / 0.1651
            let result = resolve(depth: depth(5 * scale))
            let resolution = try XCTUnwrap(result["tagSizeResolution"] as? [String: Any])
            let pose = try XCTUnwrap(result["pose"] as? [String: Any])
            XCTAssertEqual(result["id"] as? Int, 42)
            XCTAssertEqual(resolution["status"] as? String, "selected")
            XCTAssertEqual(resolution["source"] as? String, "sceneDepth-standard-match")
            XCTAssertEqual(resolution["fieldType"] as? String, "auto")
            XCTAssertTrue(resolution["competitionYear"] is NSNull, "Physical scale alone cannot establish a field year")
            XCTAssertEqual(try XCTUnwrap(resolution["tagSizeMeters"] as? Double), width, accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(resolution["estimatedEdgeMeters"] as? Double), width, accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(pose["tagSizeMeters"] as? Double), width, accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(pose["rangeMeters"] as? Double), sqrt(50) * scale, accuracy: 1e-10)
            let translation = try XCTUnwrap(pose["translation"] as? [Double])
            XCTAssertEqual(translation[0], 3 * scale, accuracy: 1e-10)
            XCTAssertEqual(translation[1], 4 * scale, accuracy: 1e-10)
            XCTAssertEqual(translation[2], 5 * scale, accuracy: 1e-10)
        }
        // A previous FTC-size result must not become a cached size for a later FRC-size print of the same ID.
        let first = resolve(depth: depth(2.5))
        let second = resolve(depth: depth(5))
        XCTAssertEqual((first["pose"] as? [String: Any])?["tagSizeMeters"] as? Double, 0.08255)
        XCTAssertEqual((second["pose"] as? [String: Any])?["tagSizeMeters"] as? Double, 0.1651)
    }
    func testAutomaticSizeScalingPreservesPixelGeometryAndScalesAllMeterQuantities() throws {
        let input = sizedRow()
        let original = try XCTUnwrap(input["pose"] as? [String: Any])
        let result = resolve(input, depth: depth(2.5))
        let pose = try XCTUnwrap(result["pose"] as? [String: Any])
        XCTAssertEqual(pose["poseError"] as? Double, 0.005)
        XCTAssertEqual(pose["secondPoseError"] as? Double, 0.0125)
        XCTAssertEqual(pose["candidateTranslationSeparationMeters"] as? Double, 0.005)
        for key in ["rotationRowMajor", "eulerDegrees"] {
            XCTAssertEqual(pose[key] as? [Double], original[key] as? [Double])
        }
        for key in ["reprojectionRMSEPixels", "secondReprojectionRMSEPixels", "poseErrorRatio",
                    "candidateRotationSeparationDegrees", "planeAngleDegrees", "opticalAxisAngleDegrees"] {
            XCTAssertEqual(pose[key] as? Double, original[key] as? Double, key)
        }
        XCTAssertEqual(pose["ambiguous"] as? Bool, false)
        XCTAssertEqual(pose["tagSizeSource"] as? String, "sceneDepth-standard-match")
    }
    func testAutomaticSizeNeverGuessesFromMissingWeakOrInvalidCenterDepth() {
        let inputs = [depth(nil, confidence: 2, mean: 5), depth(5, confidence: nil), depth(5, confidence: 0),
                      depth(5, confidence: 1), depth(5, confidence: 3), depth(0), depth(-1), depth(.nan), depth(.infinity)]
        for sample in inputs {
            let result = resolve(depth: sample)
            XCTAssertNil(result["pose"])
            XCTAssertEqual((result["tagSizeResolution"] as? [String: Any])?["status"] as? String, "unavailable")
            XCTAssertEqual(result["id"] as? Int, 42, "The detection remains available without a scaled pose")
        }
    }
    func testAutomaticSizeRejectsUnreliablePoseTrackingAndUnrecognizedPhysicalWidths() {
        let invalid = [sizedRow(poseChanges: ["ambiguous": true]),
                       sizedRow(poseChanges: ["reprojectionRMSEPixels": 3.01]),
                       sizedRow(poseChanges: ["planeAngleDegrees": 61]),
                       sizedRow(poseChanges: ["translation": [3.0, 4.0, 0.0]]),
                       sizedRow(poseChanges: ["tagSizeMeters": 0.0]),
                       sizedRow(changes: ["hamming": 1]), sizedRow(changes: ["decisionMargin": 0])]
        for input in invalid { XCTAssertNil(resolve(input)["pose"]) }
        XCTAssertNil(resolve(tracking: "limited")["pose"])
        var missing = sizedRow(); missing.removeValue(forKey: "pose")
        XCTAssertNil(resolve(missing)["pose"])
        for width in [0.01, 0.07, 0.0911, 0.2, 0.5] {
            let result = resolve(depth: depth(5 * width / 0.1651))
            XCTAssertNil(result["pose"], "Unsupported width \(width) must not silently inherit FRC scale")
            XCTAssertEqual((result["tagSizeResolution"] as? [String: Any])?["status"] as? String, "unavailable")
        }
    }
    func testAutomaticSizeSnapsOnlyWithinTheStandardTolerance() throws {
        let inside = resolve(depth: depth(2.5 * 1.0999))
        let pose = try XCTUnwrap(inside["pose"] as? [String: Any])
        XCTAssertEqual(pose["tagSizeMeters"] as? Double, 0.08255)
        XCTAssertEqual((pose["translation"] as? [Double])?[2], 2.5, "Select the standard edge rather than calibrating pose to the depth sample")
        XCTAssertNil(resolve(depth: depth(2.5 * 1.1001))["pose"])
    }
    func testAutomaticRangeGateUsesTheSelectedSizeRatherThanTheReferencePoseRange() throws {
        let fiveMeterLimit = TagDebugSettings()
        let ftc = resolve(depth: depth(2.5), settings: fiveMeterLimit)
        XCTAssertNotNil(ftc["pose"], "The reference FRC-sized pose is over 5 m, but the selected FTC-sized pose is within range")
        XCTAssertNil(resolve(depth: depth(5), settings: fiveMeterLimit)["pose"], "The selected FRC pose is beyond the maximum camera-to-tag range")
    }
    func testExplicitPresetsAndCustomWidthDoNotDependOnLiDARInference() throws {
        for (mode, width) in [("ftc", 0.08255), ("frc", 0.1651), ("custom", 0.1723456789)] {
            let configured = try settings.merging(["tagSizeMode": mode, "tagSizeMeters": width])
            let input = sizedRow(poseChanges: ["tagSizeMeters": width])
            let result = resolve(input, depth: depth(nil, confidence: nil), settings: configured, tracking: "limited")
            let original = try XCTUnwrap(input["pose"] as? [String: Any])
            let pose = try XCTUnwrap(result["pose"] as? [String: Any])
            XCTAssertEqual(pose["translation"] as? [Double], original["translation"] as? [Double])
            XCTAssertEqual(pose["tagSizeMeters"] as? Double, width)
            XCTAssertEqual((result["tagSizeResolution"] as? [String: Any])?["status"] as? String, "selected")
        }
    }
    func testSizeModesSelectCanonicalDefaultsAndPersistWithManualPrecision() throws {
        let suite = "TagSizeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = TagDebugSettings()
        XCTAssertEqual(initial.tagSizeMode, "auto")
        let ftc = try initial.merging(["tagSizeMode": "ftc"])
        XCTAssertEqual(ftc.tagSizeMode, "ftc")
        XCTAssertEqual(ftc.tagSizeMeters, 0.08255)
        let frc = try ftc.merging(["tagSizeMode": "frc"])
        XCTAssertEqual(frc.tagSizeMode, "frc")
        XCTAssertEqual(frc.tagSizeMeters, 0.1651)
        frc.persist(to: defaults)
        XCTAssertEqual(TagDebugSettings.load(from: defaults), frc)
        let manual = try frc.merging(["tagSizeMeters": 0.1723456789])
        XCTAssertEqual(manual.tagSizeMode, "custom")
        XCTAssertEqual(manual.tagSizeSource, "manual")
        manual.persist(to: defaults)
        XCTAssertEqual(TagDebugSettings.load(from: defaults), manual)
        let thresholdOnly = try manual.merging(["maxDistanceMeters": 8])
        XCTAssertEqual(thresholdOnly.tagSizeMode, "custom")
        XCTAssertEqual(thresholdOnly.tagSizeMeters, 0.1723456789)
        let invalidModes: [Any] = ["unknown", "FTC", 1, true, NSNull()]
        for value in invalidModes {
            XCTAssertThrowsError(try initial.merging(["tagSizeMode": value]))
        }
    }
    func testLegacySizeMigrationEnablesAutoOnlyForUnmodifiedFRCDefault() throws {
        let suite = "TagSizeLegacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for (source, width, expectedMode) in [("frc-default", 0.1651, "auto"),
                                             ("manual", 0.1651, "custom"),
                                             ("ar-two-point-edge", 0.1723456789, "custom"),
                                             ("manual", 0.0508, "custom")] {
            var legacy = TagDebugSettings().dictionary
            legacy.removeValue(forKey: "tagSizeMode")
            legacy["tagSizeSource"] = source
            legacy["tagSizeMeters"] = width
            defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: TagDebugSettings.defaultsKey)
            let loaded = TagDebugSettings.load(from: defaults)
            XCTAssertEqual(loaded.tagSizeMode, expectedMode)
            XCTAssertEqual(loaded.tagSizeMeters, width)
            if expectedMode == "custom" { XCTAssertEqual(loaded.tagSizeSource, source) }
        }
    }
    func testFieldYearPresetsUseTheirSeasonWidthsAndRecordTheOperatorSelection() throws {
        let presets: [(String, Int, Double)] = [("ftc", 2024, 0.0508), ("ftc", 2025, 0.1016),
            ("ftc", 2026, 0.1651), ("ftc", 2027, 0.08255),
            ("frc", 2024, 0.1651), ("frc", 2025, 0.1651), ("frc", 2026, 0.1651)]
        for (mode, year, width) in presets {
            let configured = try settings.merging(["tagSizeMode": mode, "competitionYear": year])
            XCTAssertEqual(configured.tagSizeMode, mode)
            XCTAssertEqual(configured.competitionYear, year)
            XCTAssertEqual(configured.tagSizeMeters, width)
            let result = resolve(sizedRow(poseChanges: ["tagSizeMeters": width], changes: ["id": 1]),
                                 depth: depth(nil, confidence: nil), settings: configured)
            let evidence = try XCTUnwrap(result["tagSizeResolution"] as? [String: Any])
            XCTAssertEqual(evidence["status"] as? String, "selected")
            XCTAssertEqual(evidence["fieldType"] as? String, mode)
            XCTAssertEqual(evidence["competitionYear"] as? Int, year)
            XCTAssertEqual(evidence["tagSizeMeters"] as? Double, width)
            XCTAssertTrue((evidence["label"] as? String)?.contains(String(year)) == true)
            XCTAssertEqual((result["pose"] as? [String: Any])?["tagSizeMeters"] as? Double, width)
        }
    }
    func testCenterstageResolvesBothPhysicalSizesByIDWithoutDepthAndScalesAllMetricFields() throws {
        let configured = try settings.merging(["tagSizeMode": "ftc", "competitionYear": 2024])
        for id in 1...10 {
            let expectedWidth = [7, 10].contains(id) ? 0.127 : 0.0508
            let scale = expectedWidth / 0.0508
            let input = sizedRow(poseChanges: ["tagSizeMeters": 0.0508], changes: ["id": id])
            let result = resolve(input, depth: depth(nil, confidence: nil), settings: configured, tracking: "limited")
            let pose = try XCTUnwrap(result["pose"] as? [String: Any])
            let translation = try XCTUnwrap(pose["translation"] as? [Double])
            XCTAssertEqual(pose["tagSizeMeters"] as? Double, expectedWidth, "CENTERSTAGE tag \(id)")
            XCTAssertEqual(translation[0], 3 * scale, accuracy: 1e-10)
            XCTAssertEqual(translation[1], 4 * scale, accuracy: 1e-10)
            XCTAssertEqual(translation[2], 5 * scale, accuracy: 1e-10)
            XCTAssertEqual(try XCTUnwrap(pose["rangeMeters"] as? Double), sqrt(50) * scale, accuracy: 1e-10)
            XCTAssertEqual(try XCTUnwrap(pose["poseError"] as? Double), 0.02 * scale * scale, accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(pose["secondPoseError"] as? Double), 0.05 * scale * scale, accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(pose["candidateTranslationSeparationMeters"] as? Double), 0.01 * scale, accuracy: 1e-12)
            XCTAssertEqual(pose["reprojectionRMSEPixels"] as? Double, 0.2)
            XCTAssertEqual(pose["poseErrorRatio"] as? Double, 0.4)
            XCTAssertEqual((result["tagSizeResolution"] as? [String: Any])?["competitionYear"] as? Int, 2024)
        }
    }
    func testCenterstageUnknownOrMalformedIDsDoNotInheritTheReferenceWidth() throws {
        let configured = try settings.merging(["tagSizeMode": "ftc", "competitionYear": 2024])
        let invalidIDs: [Any] = [-1, 0, 11, 42, 7.5, Double.nan, NSNull()]
        for id in invalidIDs {
            let result = resolve(sizedRow(poseChanges: ["tagSizeMeters": 0.0508], changes: ["id": id]), settings: configured)
            XCTAssertNil(result["pose"])
            let evidence = try XCTUnwrap(result["tagSizeResolution"] as? [String: Any])
            XCTAssertEqual(evidence["status"] as? String, "unavailable")
            XCTAssertEqual(evidence["fieldType"] as? String, "ftc")
            XCTAssertEqual(evidence["competitionYear"] as? Int, 2024)
            XCTAssertTrue(evidence["tagSizeMeters"] is NSNull)
            XCTAssertTrue((evidence["reason"] as? String)?.contains("Settings") == true)
        }
    }
    func testCompetitionYearChangesPersistAndManualOrAutoSelectionClearsTheYear() throws {
        let suite = "TagFieldYearTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let currentFTC = try settings.merging(["tagSizeMode": "ftc"])
        XCTAssertEqual(currentFTC.competitionYear, 2027)
        let previousFTC = try currentFTC.merging(["competitionYear": 2025])
        XCTAssertEqual(previousFTC.tagSizeMode, "ftc")
        XCTAssertEqual(previousFTC.competitionYear, 2025)
        XCTAssertEqual(previousFTC.tagSizeMeters, 0.1016)
        previousFTC.persist(to: defaults)
        XCTAssertEqual(TagDebugSettings.load(from: defaults), previousFTC)
        let thresholdOnly = try previousFTC.merging(["maxDistanceMeters": 8])
        XCTAssertEqual(thresholdOnly.competitionYear, 2025)
        XCTAssertEqual(thresholdOnly.tagSizeMeters, 0.1016)
        let currentFRC = try previousFTC.merging(["tagSizeMode": "frc"])
        XCTAssertEqual(currentFRC.competitionYear, 2026)
        XCTAssertEqual(currentFRC.tagSizeMeters, 0.1651)
        let custom = try previousFTC.merging(["tagSizeMeters": 0.1723456789])
        XCTAssertEqual(custom.tagSizeMode, "custom")
        XCTAssertEqual(custom.competitionYear, 0)
        XCTAssertEqual(custom.tagSizeMeters, 0.1723456789)
        let automatic = try previousFTC.merging(["tagSizeMode": "auto"])
        XCTAssertEqual(automatic.competitionYear, 0)
        XCTAssertEqual(automatic.tagSizeMeters, 0.1651)
    }
    func testCompetitionYearsRejectUnsupportedFieldPairsAndMalformedNumbers() throws {
        let invalid: [[String: Any]] = [["tagSizeMode": "ftc", "competitionYear": 2023],
            ["tagSizeMode": "ftc", "competitionYear": 2028], ["tagSizeMode": "frc", "competitionYear": 2023],
            ["tagSizeMode": "frc", "competitionYear": 2027], ["tagSizeMode": "auto", "competitionYear": 2026],
            ["tagSizeMode": "custom", "competitionYear": 2027]]
        for changes in invalid { XCTAssertThrowsError(try settings.merging(changes)) }
        let malformed: [Any] = [true, "2026", 2026.5, -1, Double.nan, Double.infinity, NSNull()]
        let field = try settings.merging(["tagSizeMode": "ftc"])
        for year in malformed { XCTAssertThrowsError(try field.merging(["competitionYear": year])) }
    }
    func testSixInchSampleDoesNotBecomeSixAndAHalfInchFieldTag() throws {
        for width in [0.1524, 0.1651] {
            let result = resolve(depth: depth(5 * width / 0.1651))
            let evidence = try XCTUnwrap(result["tagSizeResolution"] as? [String: Any])
            XCTAssertEqual(evidence["tagSizeMeters"] as? Double, width)
            XCTAssertEqual(evidence["relativeTolerance"] as? Double, 0.03)
            XCTAssertEqual((result["pose"] as? [String: Any])?["tagSizeMeters"] as? Double, width)
        }
        let midpointWidth = (0.1524 + 0.1651) / 2
        XCTAssertNil(resolve(depth: depth(5 * midpointWidth / 0.1651))["pose"], "Intermediate large sizes must not be assigned an unsupported scale")
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
        legacy.removeValue(forKey: "tagSizeMode")
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
        legacy.removeValue(forKey: "tagSizeMode")
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
    func testDistanceDeltaThresholdMigratesAndPersistsIndependentlyOfDepthWarnings() throws {
        let suite = "DistanceDeltaSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = TagDebugSettings().dictionary
        legacy.removeValue(forKey: "distanceDeltaThresholdMeters")
        legacy.removeValue(forKey: "tagSizeMode")
        legacy["tagSizeMeters"] = 0.1723456789
        legacy["tagSizeSource"] = "ar-two-point-edge"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: TagDebugSettings.defaultsKey)
        let loaded = TagDebugSettings.load(from: defaults)
        XCTAssertEqual(loaded.distanceDeltaThresholdMeters, 0.15)
        let changed = try loaded.merging(["distanceDeltaThresholdMeters": 0.215])
        XCTAssertEqual(changed.warningDepthDifferenceMeters, loaded.warningDepthDifferenceMeters)
        XCTAssertEqual(changed.rejectDepthDifferenceMeters, loaded.rejectDepthDifferenceMeters)
        XCTAssertEqual(changed.tagSizeMeters, loaded.tagSizeMeters)
        XCTAssertEqual(changed.tagSizeSource, loaded.tagSizeSource)
        changed.persist(to: defaults)
        XCTAssertEqual(TagDebugSettings.load(from: defaults), changed)
        XCTAssertEqual(try changed.merging(["distanceDeltaThresholdMeters": 0]).distanceDeltaThresholdMeters, 0)
        let invalid: [Any] = [-0.01, 10.01, Double.nan, Double.infinity, true, "0.2"]
        for value in invalid {
            XCTAssertThrowsError(try loaded.merging(["distanceDeltaThresholdMeters": value]))
        }
    }
    func testFloorLevelingDefaultsOffAndPersistsAsStrictBoolean() throws {
        let suite = "FloorLevelingSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = TagDebugSettings().dictionary
        legacy.removeValue(forKey: "levelFloorWithGravity")
        legacy.removeValue(forKey: "tagSizeMode")
        legacy["tagSizeMeters"] = 0.1723456789
        legacy["tagSizeSource"] = "ar-two-point-edge"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: TagDebugSettings.defaultsKey)
        let loaded = TagDebugSettings.load(from: defaults)
        XCTAssertFalse(loaded.levelFloorWithGravity)
        let enabled = try loaded.merging(["levelFloorWithGravity": true])
        XCTAssertTrue(enabled.levelFloorWithGravity)
        XCTAssertEqual(enabled.tagSizeMeters, loaded.tagSizeMeters)
        XCTAssertEqual(enabled.tagSizeSource, loaded.tagSizeSource)
        enabled.persist(to: defaults)
        XCTAssertEqual(TagDebugSettings.load(from: defaults), enabled)
        XCTAssertFalse(try enabled.merging(["levelFloorWithGravity": false]).levelFloorWithGravity)
        XCTAssertThrowsError(try enabled.merging(["levelFloorWithGravity": 1]))
        XCTAssertThrowsError(try enabled.merging(["levelFloorWithGravity": "true"]))
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
