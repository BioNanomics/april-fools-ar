import XCTest
import simd

final class TagCameraRangesTests: XCTestCase {
    private let k = simd_float3x3(columns: ([100, 0, 0], [0, 200, 0], [50, 80, 1]))
    private func context(intrinsics: simd_float3x3? = nil) -> TagCameraRangesContext {
        TagCameraRangesContext(intrinsics: intrinsics ?? k, frameID: "source-frame", segmentID: "segment-A", timestamp: 123)
    }
    private func row(depth: Any = 5.0, confidence: Any = 2, center: Any = [110, 240],
                     translation: Any = [3, 4, 5]) -> [String: Any] {
        ["id": 42, "center": center,
         "depth": ["centerDepthMeters": depth, "centerConfidence": confidence],
         "pose": ["translation": translation, "rangeMeters": 5],
         "debug": ["depthDifferenceMeters": 0, "status": "valid"],
         "floorHeight": ["available": false, "reason": "floorNotSelected"]]
    }
    private func number(_ value: Any?) -> Double? { TagDebugMath.number(value) }

    func testOffAxisLidarAndTagCompareEuclideanRangesWhileRetainingOpticalZ() throws {
        let result = TagCameraRanges.evaluate(row(), context: context())
        let range = sqrt(50.0)
        XCTAssertEqual(try XCTUnwrap(number(result["lidarRangeMeters"])), range, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(number(result["tagRangeMeters"])), range, accuracy: 1e-9,
                       "Pose norm must be recomputed, not copied from the deliberately wrong cached range")
        XCTAssertEqual(number(result["lidarDepthZMeters"]), 5)
        XCTAssertEqual(number(result["tagDepthZMeters"]), 5)
        XCTAssertNotEqual(number(result["lidarRangeMeters"]), number(result["lidarDepthZMeters"]))
        let farther = TagCameraRanges.evaluate(row(depth: 6), context: context())
        XCTAssertEqual(try XCTUnwrap(number(farther["lidarRangeMeters"])), sqrt(72), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(number(farther["tagRangeMeters"])), range, accuracy: 1e-9)
    }

    func testRawRangesRemainAvailableWithoutFloorAndDoNotChangePoseQualityOrDepthDelta() throws {
        var input = row()
        input["debug"] = ["status": "ambiguous", "severity": "warning", "depthDifferenceMeters": 0.2]
        let enriched = TagCameraRanges.enrich(input, context: context())
        let ranges = try XCTUnwrap(enriched["cameraRanges"] as? [String: Any])
        XCTAssertEqual(ranges["lidarAvailable"] as? Bool, true)
        XCTAssertEqual(ranges["tagAvailable"] as? Bool, true)
        XCTAssertEqual((enriched["floorHeight"] as? [String: Any])?["available"] as? Bool, false)
        let debug = try XCTUnwrap(enriched["debug"] as? [String: Any])
        XCTAssertEqual(debug["status"] as? String, "ambiguous")
        XCTAssertEqual(number(debug["depthDifferenceMeters"]), 0.2)
        let debugRanges = try XCTUnwrap(debug["cameraRanges"] as? [String: Any])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: ranges, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: debugRanges, options: [.sortedKeys]))
        XCTAssertEqual(ranges["frameId"] as? String, "source-frame")
        XCTAssertEqual(ranges["segmentId"] as? String, "segment-A")
        XCTAssertEqual(number(ranges["timestamp"]), 123)
        XCTAssertNil(enriched["measurement"])
    }

    func testInvalidCenterOrIntrinsicsOmitLidarRangeButPreserveAcceptedOpticalDepth() {
        var zeroFocal = k; zeroFocal.columns.0.x = 0
        var nonfinite = k; nonfinite.columns.2.y = .nan
        for invalid in [zeroFocal, nonfinite] {
            let result = TagCameraRanges.evaluate(row(), context: context(intrinsics: invalid))
            XCTAssertNil(number(result["lidarRangeMeters"]))
            XCTAssertEqual(number(result["lidarDepthZMeters"]), 5)
            XCTAssertNotNil(number(result["tagRangeMeters"]))
        }
        for center in ([[-1, 2], [Double.nan, 2], [110], [true, 240], "110,240"] as [Any]) {
            let result = TagCameraRanges.evaluate(row(center: center), context: context())
            XCTAssertNil(number(result["lidarRangeMeters"]))
            XCTAssertEqual(number(result["lidarDepthZMeters"]), 5)
        }
    }

    func testUnknownOrMalformedConfidenceAndDepthNeverProduceLidarRange() {
        for confidence in ([0, 3, 1.5, true, NSNull(), "2"] as [Any]) {
            let result = TagCameraRanges.evaluate(row(confidence: confidence), context: context())
            XCTAssertNil(number(result["lidarRangeMeters"]))
            XCTAssertEqual(result["lidarAvailable"] as? Bool, false)
            XCTAssertNotNil(number(result["tagRangeMeters"]))
        }
        for depth in ([0, -1, Double.nan, Double.infinity, true, "5"] as [Any]) {
            let result = TagCameraRanges.evaluate(row(depth: depth), context: context())
            XCTAssertNil(number(result["lidarRangeMeters"]))
        }
        for confidence in [1, 2] {
            XCTAssertNotNil(number(TagCameraRanges.evaluate(row(confidence: confidence), context: context())["lidarRangeMeters"]))
        }
    }

    func testMalformedPoseDoesNotHideIndependentlyValidLidarRange() {
        for translation in ([[0, 0, 0], [0, 0, -1], [Double.nan, 0, 5], [0, 5], [true, 4, 5], "3,4,5"] as [Any]) {
            let result = TagCameraRanges.evaluate(row(translation: translation), context: context())
            XCTAssertNil(number(result["tagRangeMeters"]))
            XCTAssertEqual(result["tagAvailable"] as? Bool, false)
            XCTAssertNotNil(number(result["lidarRangeMeters"]))
            XCTAssertTrue(JSONSerialization.isValidJSONObject(result))
        }
    }
}
