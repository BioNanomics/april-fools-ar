import XCTest
import simd

final class TagFloorHeightTests: XCTestCase {
    private let k = simd_float3x3(columns: ([400, 0, 0], [0, 600, 0], [160, 120, 1]))
    private let cameraPose = simd_float4x4(columns: ([0, 1, 0, 0], [-1, 0, 0, 0], [0, 0, 1, 0], [1, 2, 3, 1]))
    private func floor(segment: String = "segment-A", normal: SIMD3<Float> = [0, 1, 0]) -> SpatialPlane {
        SpatialPlane(id: "confirmed-floor", classification: "floor", origin: .zero, normal: normal,
            vertices: [[-2, 0, -2], [2, 0, -2], [2, 0, 2], [-2, 0, 2]],
            segmentID: segment, frameID: "floor-frame", timestamp: 90)
    }
    private func context(floor: SpatialPlane?, age: Double = 0.1, tracking: String = "normal",
                         frame: String = "source-frame", pose: simd_float4x4? = nil) -> TagFloorHeightContext {
        TagFloorHeightContext(floor: floor, cameraToWorld: pose ?? cameraPose, intrinsics: k,
            settings: TagDebugSettings(), tracking: tracking, frameID: frame, segmentID: "segment-A",
            timestamp: 100, frameAgeSeconds: age)
    }
    private func detection(depth: Double? = 2, confidence: Int? = 2,
                           poseChanges: [String: Any] = [:], changes: [String: Any] = [:]) -> [String: Any] {
        // At center (200,180), a 2 m optical depth unprojects to (.2,.2,2).
        // A 2.1 m PnP solution has (.21,.21,2.1), and still agrees within the reject threshold.
        var pose: [String: Any] = ["translation": [0.21, 0.21, 2.1],
            "rotationRowMajor": [1, 0, 0, 0, 1, 0, 0, 0, 1], "eulerDegrees": [0, 0, 0],
            "rangeMeters": 2.1209, "planeAngleDegrees": 8, "opticalAxisAngleDegrees": 8,
            "reprojectionRMSEPixels": 0.5, "ambiguous": false, "tagSizeMeters": 0.1651]
        pose.merge(poseChanges) { _, new in new }
        var row: [String: Any] = ["id": 42, "center": [200, 180], "hamming": 0,
            "decisionMargin": 80, "pose": pose, "corners": [[180, 160], [220, 160], [220, 200], [180, 200]]]
        row.merge(changes) { _, new in new }
        var samples = TagDepthSamples()
        samples.centerDepthMeters = depth; samples.rawCenterDepthMeters = depth
        samples.centerConfidence = confidence; samples.meanDepthMeters = depth
        samples.reason = depth == nil ? "Scene depth unavailable" : "Fixture center"
        return TagDebugMath.enrich(row, depth: samples, settings: TagDebugSettings(), tracking: "normal")
    }
    private func assertUnavailable(_ value: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value["available"] as? Bool, false, file: file, line: line)
        XCTAssertNil(TagDebugMath.number(value["meters"]), "Unavailable height must not become a fake zero", file: file, line: line)
        XCTAssertNotNil(value["reason"] as? String, file: file, line: line)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(value), file: file, line: line)
    }

    func testAcceptedLidarCenterWinsAndUsesTheExactSourceFrameCamera() throws {
        let first = TagFloorHeight.evaluate(detection(), context: context(floor: floor()))
        XCTAssertEqual(first["available"] as? Bool, true)
        XCTAssertEqual(first["source"] as? String, "sceneDepth")
        // Camera local (.2,-.2,-2), rotated 90° around Z then translated (1,2,3), is world (1.2,2.2,1).
        XCTAssertEqual(try XCTUnwrap(TagDebugMath.number(first["meters"])), 2.2, accuracy: 1e-5)
        XCTAssertEqual(first["frameId"] as? String, "source-frame")
        XCTAssertEqual(first["segmentId"] as? String, "segment-A")
        XCTAssertEqual(first["floorId"] as? String, "confirmed-floor")
        var laterCamera = cameraPose; laterCamera.columns.3.y = 10
        let later = TagFloorHeight.evaluate(detection(), context: context(floor: floor(), frame: "later-frame", pose: laterCamera))
        XCTAssertEqual(try XCTUnwrap(TagDebugMath.number(later["meters"])), 10.2, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(TagDebugMath.number(first["meters"])), 2.2, accuracy: 1e-5)
    }

    func testMissingOrRejectedDepthUsesExplicitValidPoseFallback() throws {
        for row in [detection(depth: nil, confidence: nil), detection(depth: nil, confidence: 0),
                    detection(depth: nil, confidence: 3)] {
            let result = TagFloorHeight.evaluate(row, context: context(floor: floor()))
            XCTAssertEqual(result["available"] as? Bool, true)
            XCTAssertEqual(result["source"] as? String, "tagPose")
            XCTAssertEqual(try XCTUnwrap(TagDebugMath.number(result["meters"])), 2.21, accuracy: 1e-5)
        }
    }

    func testConfirmedSlopedFloorUsesPlumbHeightRatherThanNormalDistance() throws {
        // At world (1.2,2.2,1), plane y=.1x+.2z has y=.32: vertical height=1.88 m.
        let result = TagFloorHeight.evaluate(detection(), context: context(floor: floor(normal: [-0.1, 1, -0.2])))
        XCTAssertEqual(result["available"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(TagDebugMath.number(result["meters"])), 1.88, accuracy: 1e-5)
    }

    func testPoseQualityAndKnownRejectedDepthMismatchBlockAllSources() {
        let rejectedRows = [detection(poseChanges: ["ambiguous": true]),
            detection(poseChanges: ["rangeMeters": 6]), detection(poseChanges: ["planeAngleDegrees": 80]),
            detection(poseChanges: ["reprojectionRMSEPixels": 4]), detection(changes: ["hamming": 1]),
            detection(changes: ["decisionMargin": 0]), detection(poseChanges: ["translation": [0, 0, -1]]),
            detection(depth: 2.5), detection(depth: nil, poseChanges: ["ambiguous": true])]
        for row in rejectedRows {
            assertUnavailable(TagFloorHeight.evaluate(row, context: context(floor: floor())))
        }
        let warning = TagFloorHeight.evaluate(detection(depth: 1.98), context: context(floor: floor()))
        XCTAssertEqual(warning["available"] as? Bool, true, "A 0.12 m discrepancy is warning-only, below reject threshold")
    }

    func testMissingForeignOrInvalidFloorAndStaleTrackingProduceNoNumericHeight() {
        for value in [context(floor: nil), context(floor: floor(segment: "old-segment")),
            context(floor: floor(normal: [1, 0.001, 0])), context(floor: floor(), age: -0.01),
            context(floor: floor(), age: 0.401), context(floor: floor(), age: .nan),
            context(floor: floor(), tracking: "limited")] {
            assertUnavailable(TagFloorHeight.evaluate(detection(), context: value))
        }
        XCTAssertEqual(TagFloorHeight.evaluate(detection(), context: context(floor: nil))["reason"] as? String, "floorNotSelected")
    }

    func testMalformedCameraTransformsCannotFabricateAZeroHeight() {
        var scaled = cameraPose; scaled.columns.0 *= 2
        var sheared = cameraPose; sheared.columns.1.x += 0.5
        var perspective = cameraPose; perspective.columns.0.w = 0.1
        var nonfinite = cameraPose; nonfinite.columns.3.y = .nan
        let zero = simd_float4x4(diagonal: SIMD4<Float>(repeating: 0))
        for pose in [zero, scaled, sheared, perspective, nonfinite] {
            assertUnavailable(TagFloorHeight.evaluate(detection(), context: context(floor: floor(), pose: pose)))
        }
    }

    func testEnrichmentDuplicatesHeightProvenanceWithoutCreatingManualMeasurements() throws {
        let row = TagFloorHeight.enrich(detection(), context: context(floor: floor()))
        let height = try XCTUnwrap(row["floorHeight"] as? [String: Any])
        let debugHeight = try XCTUnwrap((row["debug"] as? [String: Any])?["floorHeight"] as? [String: Any])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: height, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: debugHeight, options: [.sortedKeys]))
        XCTAssertEqual((row["id"] as? NSNumber)?.intValue, 42)
        XCTAssertNil(row["measurement"])
        XCTAssertNil(row["measurementCompleted"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(row))
    }

    func testUnitDisplayLeavesRawMeterGeometryAndProvenanceUnchanged() throws {
        let height = TagFloorHeight.evaluate(detection(), context: context(floor: floor()))
        let before = try JSONSerialization.data(withJSONObject: height, options: [.sortedKeys])
        let meters = try XCTUnwrap(TagDebugMath.number(height["meters"]))
        XCTAssertEqual(HeightDisplayFormatter.string(meters: meters), "220.0 cm (7 ft 2.6 in)")
        XCTAssertEqual(HeightDisplayFormatter.string(meters: meters, showImperial: false), "220.0 cm")
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: height, options: [.sortedKeys]), before)
        XCTAssertEqual(TagDebugMath.number(height["meters"]), meters)
        XCTAssertEqual(height["worldMeters"] as? [Double], [Double(Float(1.2)), Double(Float(2.2)), 1])
    }
}
