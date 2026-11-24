import XCTest
import simd

final class TagGravityOrientationTests: XCTestCase {
    private let opticalAxes = simd_float4x4(diagonal: [1, -1, -1, 1])
    private func rotation(_ angle: Float, _ axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: axis))
    }
    private func context(camera: simd_float4x4 = matrix_identity_float4x4, tracking: String = "normal",
                         age: Double = 0.05, frame: String = "source-frame", segment: String = "A") -> GravityRelativeTagOrientationContext {
        GravityRelativeTagOrientationContext(cameraToWorld: camera, settings: TagDebugSettings(), tracking: tracking,
            frameID: frame, segmentID: segment, timestamp: 100, frameAgeSeconds: age)
    }
    private func detection(rotation: simd_float4x4 = matrix_identity_float4x4,
                           translation: SIMD3<Float> = [0, 0, 3], poseChanges: [String: Any] = [:]) -> [String: Any] {
        let rowMajor = (0..<9).map { Double(rotation[$0 % 3][$0 / 3]) }
        var pose: [String: Any] = ["rotationRowMajor": rowMajor, "translation": [translation.x, translation.y, translation.z],
            "rangeMeters": Double(simd_length(translation)), "eulerDegrees": [0, 0, 0],
            "planeAngleDegrees": 20.0, "reprojectionRMSEPixels": 0.5, "opticalAxisAngleDegrees": 0,
            "ambiguous": false]
        pose.merge(poseChanges) { _, new in new }
        return ["id": 42, "pose": pose, "decisionMargin": 80, "hamming": 0, "center": [160, 120]]
    }
    private func assertUnavailable(_ value: [String: Any], reason: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value["available"] as? Bool, false, file: file, line: line)
        XCTAssertTrue(value["tiltFromVerticalDegrees"] is NSNull, file: file, line: line)
        XCTAssertTrue(value["twistDegrees"] is NSNull, file: file, line: line)
        XCTAssertTrue(value["planeLeanFromVerticalDegrees"] is NSNull, file: file, line: line)
        XCTAssertTrue(value["uprightRotationClockwiseDegrees"] is NSNull, file: file, line: line)
        XCTAssertTrue(value["normalWorld"] is NSNull, file: file, line: line)
        if let reason { XCTAssertEqual(value["reason"] as? String, reason, file: file, line: line) }
        XCTAssertTrue(JSONSerialization.isValidJSONObject(value), file: file, line: line)
    }

    func testUprightTagHasRealZeroAnglesWithoutFloorDepthOrEulerAngles() throws {
        let row = detection(poseChanges: ["eulerDegrees": NSNull()])
        let value = GravityRelativeTagOrientation.evaluate(row, context: context())
        XCTAssertEqual(value["available"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(value["tiltFromVerticalDegrees"] as? Double), 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(value["twistDegrees"] as? Double), 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(value["planeLeanFromVerticalDegrees"] as? Double), 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(value["uprightRotationClockwiseDegrees"] as? Double), 0, accuracy: 1e-6)
        XCTAssertEqual(value["normalWorld"] as? [Double], [0, 0, -1])
        XCTAssertEqual(value["upWorld"] as? [Double], [0, 1, 0])
        XCTAssertNil(row["floorHeight"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(value))
    }

    func testPhonePitchRollYawAndPositionDoNotChangeFixedTagOrientation() throws {
        let worldTag = opticalAxes * rotation(25 * .pi/180, [1, 0, 0]) * rotation(-18 * .pi/180, [0, 0, 1])
        let cameras = [matrix_identity_float4x4,
            rotation(0.31, [1, 0, 0]) * rotation(-0.24, [0, 1, 0]) * rotation(0.73, [0, 0, 1]),
            rotation(-0.2, [0, 1, 0]) * rotation(-1.1, [0, 0, 1])]
        for (index, source) in cameras.enumerated() {
            var camera = source
            camera.columns.3 = [Float(index), 1.5, -0.2, 1]
            let relative = simd_inverse(camera * opticalAxes) * worldTag
            let value = GravityRelativeTagOrientation.evaluate(detection(rotation: relative), context: context(camera: camera))
            XCTAssertEqual(value["available"] as? Bool, true)
            XCTAssertEqual(try XCTUnwrap(value["tiltFromVerticalDegrees"] as? Double), 25, accuracy: 1e-4)
            XCTAssertEqual(try XCTUnwrap(value["twistDegrees"] as? Double), -18, accuracy: 1e-4)
            let actual = try XCTUnwrap(value["worldFromTagRotationRowMajor"] as? [Double])
            for element in 0..<9 { XCTAssertEqual(actual[element], Double(worldTag[element % 3][element / 3]), accuracy: 1e-5) }
        }
    }

    func testHorizontalPlaneKeepsTiltButHasNoUprightTwist() throws {
        let value = GravityRelativeTagOrientation.evaluate(detection(rotation: rotation(.pi/2, [1, 0, 0])), context: context())
        XCTAssertEqual(value["available"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(value["tiltFromVerticalDegrees"] as? Double), 90, accuracy: 0.03)
        XCTAssertEqual(value["twistAvailable"] as? Bool, false)
        XCTAssertTrue(value["twistDegrees"] is NSNull)
        XCTAssertEqual(try XCTUnwrap(value["planeLeanFromVerticalDegrees"] as? Double),90,accuracy:0.03)
        XCTAssertTrue(value["uprightRotationClockwiseDegrees"] is NSNull)
        XCTAssertEqual(value["twistReason"] as? String, "horizontalTagPlane")
    }

    func testCanonicalGravityNamesRetainLegacyValuesAndExactFrameProvenance() throws {
        for poseRotation in [matrix_identity_float4x4,
                             rotation(0.4,[1,0,0]) * rotation(-0.3,[0,0,1]),
                             rotation(.pi/2,[1,0,0])] {
            let value = GravityRelativeTagOrientation.evaluate(detection(rotation:poseRotation),context:context())
            XCTAssertEqual(value["available"] as? Bool,true)
            for (canonical,legacy) in [("planeLeanFromVerticalDegrees","tiltFromVerticalDegrees"),
                                       ("uprightRotationClockwiseDegrees","twistDegrees")] {
                if let old = value[legacy] as? Double {
                    XCTAssertEqual(try XCTUnwrap(value[canonical] as? Double),old,accuracy:1e-12)
                } else {
                    XCTAssertTrue(value[legacy] is NSNull)
                    XCTAssertTrue(value[canonical] is NSNull)
                }
            }
            XCTAssertEqual(value["frameId"] as? String,"source-frame")
            XCTAssertEqual(value["segmentId"] as? String,"A")
            XCTAssertEqual(value["coordinateFrame"] as? String,"gravity-aligned-world-y-up")
            XCTAssertTrue((value["angleConvention"] as? String)?.contains("legacy tilt/twist fields are aliases") == true)
            let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONSerialization.data(withJSONObject:value)) as? [String:Any])
            XCTAssertEqual(roundTrip["planeLeanFromVerticalDegrees"] as? Double,value["planeLeanFromVerticalDegrees"] as? Double)
            XCTAssertEqual(roundTrip["uprightRotationClockwiseDegrees"] as? Double,value["uprightRotationClockwiseDegrees"] as? Double)
        }
    }

    func testInvalidTrackingFrameQualityAndAmbiguityNeverBecomeZeroAngles() {
        for input in [context(tracking: "limited"), context(age: 0.401), context(age: -0.01),
                      context(age: .nan), context(frame: ""), context(segment: "")] {
            assertUnavailable(GravityRelativeTagOrientation.evaluate(detection(), context: input))
        }
        for ambiguous: Any in [true, NSNull(), 0, 1] {
            assertUnavailable(GravityRelativeTagOrientation.evaluate(detection(poseChanges: ["ambiguous": ambiguous]), context: context()), reason: "ambiguousPose")
        }
        for changes: [String: Any] in [["rotationRowMajor": [1, 0]], ["rotationRowMajor": [true, 0, 0, 0, 1, 0, 0, 0, 1]],
                                      ["rotationRowMajor": [1, 0, 0, 0, 1, 0, 0, 0, -1]],
                                      ["translation": [0, 0, false]], ["reprojectionRMSEPixels": true]] {
            assertUnavailable(GravityRelativeTagOrientation.evaluate(detection(poseChanges: changes), context: context()))
        }
        var camera = matrix_identity_float4x4; camera.columns.0.x = 2
        assertUnavailable(GravityRelativeTagOrientation.evaluate(detection(), context: context(camera: camera)))
        assertUnavailable(GravityRelativeTagOrientation.evaluate(detection(translation: [0, 0, 100]), context: context()), reason: "tooFar")
    }

    func testEnrichmentPreservesRawPoseAndHeightAndRecordsExactFrame() throws {
        var row = detection()
        row["floorHeight"] = ["available": true, "meters": 2.2]
        let before = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        let result = GravityRelativeTagOrientation.enrich(row, context: context())
        let value = try XCTUnwrap(result["gravityOrientation"] as? [String: Any])
        let debug = try XCTUnwrap((result["debug"] as? [String: Any])?["gravityOrientation"] as? [String: Any])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: debug, options: [.sortedKeys]))
        XCTAssertEqual(value["frameId"] as? String, "source-frame")
        XCTAssertEqual(value["segmentId"] as? String, "A")
        XCTAssertEqual(value["timestamp"] as? Double, 100)
        XCTAssertEqual((result["floorHeight"] as? [String: Any])?["meters"] as? Double, 2.2)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), before)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(result))
    }

    func testMatchingCameraPoseSolvesHeightAndTiltTogether() throws {
        var camera = rotation(-0.15, [1, 0, 0]) * rotation(0.2, [0, 1, 0]) * rotation(0.3, [0, 0, 1])
        camera.columns.3 = [0.1, 1.5, 0.2, 1]
        let worldFromOptical = camera * opticalAxes
        let centerWorld: SIMD4<Float> = [0.3, 2.2, -3, 1]
        let centerOptical = simd_inverse(worldFromOptical) * centerWorld
        let worldTag = opticalAxes * rotation(0.2, [1, 0, 0])
        let row = detection(rotation: simd_inverse(worldFromOptical) * worldTag,
                            translation: [centerOptical.x, centerOptical.y, centerOptical.z])
        let oriented = GravityRelativeTagOrientation.enrich(row, context: context(camera: camera))
        let floor = SpatialPlane(id: "floor", classification: "floor", origin: .zero, normal: [0, 1, 0],
            vertices: [[-2, 0, -4], [2, 0, -4], [2, 0, 1], [-2, 0, 1]], segmentID: "A", frameID: "floor-frame", timestamp: 90)
        let result = TagFloorHeight.enrich(oriented, context: TagFloorHeightContext(floor: floor, cameraToWorld: camera,
            intrinsics: simd_float3x3(columns: ([400, 0, 0], [0, 400, 0], [160, 120, 1])), settings: TagDebugSettings(),
            tracking: "normal", frameID: "source-frame", segmentID: "A", timestamp: 100, frameAgeSeconds: 0.05))
        let height = try XCTUnwrap(result["floorHeight"] as? [String: Any])
        XCTAssertEqual(height["available"] as? Bool, true)
        XCTAssertEqual(height["source"] as? String, "tagPose")
        XCTAssertEqual(try XCTUnwrap(height["meters"] as? Double), 2.2, accuracy: 1e-5)
        let orientation = try XCTUnwrap(result["gravityOrientation"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(orientation["tiltFromVerticalDegrees"] as? Double), 0.2 * 180 / .pi, accuracy: 1e-4)
    }
}
