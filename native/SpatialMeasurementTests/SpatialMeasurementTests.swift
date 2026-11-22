import XCTest
import simd

final class SpatialMeasurementTests: XCTestCase {
    private func plane(normal: SIMD3<Float> = [0, 1, 0], origin: SIMD3<Float> = .zero,
                       classification: String = "floor", segment: String = "segment-A") -> SpatialPlane {
        SpatialPlane(id: "floor-A", classification: classification, origin: origin, normal: normal,
                     vertices: [[-2, 0, -2], [2, 0, -2], [2, 0, 2], [-2, 0, 2]],
                     segmentID: segment, frameID: "floor-frame", timestamp: 10)
    }
    private func point(_ world: SIMD3<Float>, frame: String = "frame-A", segment: String = "segment-A",
                       confidence: Int = 2, depth: Double = 2) -> SpatialPoint {
        SpatialPoint(world: world, record: ["segmentId": segment, "frameId": frame, "timestamp": 11.5,
            "confidence": confidence, "depthMeters": depth, "source": "sceneDepth",
            "worldMeters": SpatialMeasurementMath.array(world), "pixel": [120, 240]])
    }
    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-5, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-5, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 1e-5, file: file, line: line)
    }
    private func completeDistance(_ state: inout SpatialMeasurementState, offset: Float = 0) throws -> SpatialMeasurement {
        state.setMode(.distance)
        XCTAssertNil(try state.append(point([offset, 0, -2]), tracking: "normal", frameAgeSeconds: 0.1))
        return try XCTUnwrap(state.append(point([offset + 3, 4, -2], frame: "frame-B"), tracking: "normal", frameAgeSeconds: 0.1))
    }

    func testVerticalIntersectionIsWorldVerticalForHorizontalAndSlopedFloors() throws {
        assertVector(try SpatialMeasurementMath.verticalFoot(of: [1, 2, -3], onto: plane(origin: [0, -0.5, 0])), [1, -0.5, -3])
        // Plane y = 0.1x + 0.2z. A plumb height keeps x/z, unlike shortest normal distance.
        assertVector(try SpatialMeasurementMath.verticalFoot(of: [2, 3, 4], onto: plane(normal: [-0.1, 1, -0.2])), [2, 1, 4])
        assertVector(try SpatialMeasurementMath.verticalFoot(of: [2, 3, 4], onto: plane(normal: [0.1, -1, 0.2])), [2, 1, 4])
    }

    func testInvalidFloorAndTargetGeometryCannotProduceHeight() {
        for normal in ([[1, 0.001, 0], .zero, [.nan, 1, 0]] as [SIMD3<Float>]) {
            XCTAssertThrowsError(try SpatialMeasurementMath.verticalFoot(of: [0, 1, 0], onto: plane(normal: normal)))
        }
        for target in ([[0, -0.01, 0], [0, 31, 0], [.infinity, 1, 0]] as [SIMD3<Float>]) {
            XCTAssertThrowsError(try SpatialMeasurementMath.verticalFoot(of: target, onto: plane()))
        }
    }

    func testFloorRequiresCurrentSegmentFreshNormalTrackingAndAcceptedClassification() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        state.setMode(.height)
        XCTAssertEqual(state.mode, .selectFloor)
        for tracking in ["limited", "unavailable"] {
            XCTAssertThrowsError(try state.confirmFloor(plane(), tracking: tracking, frameAgeSeconds: 0))
        }
        for age in [-0.01, 0.501, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try state.confirmFloor(plane(), tracking: "normal", frameAgeSeconds: age))
        }
        for rejected in [plane(segment: "old-segment"), plane(classification: "wall"), plane(classification: "table")] {
            XCTAssertThrowsError(try state.confirmFloor(rejected, tracking: "normal", frameAgeSeconds: 0))
        }
        XCTAssertNil(state.floor)
        try state.confirmFloor(plane(classification: "unclassified"), tracking: "normal", frameAgeSeconds: 0.5)
        XCTAssertEqual(state.mode, .height)
        XCTAssertEqual(state.floor?.id, "floor-A")
    }

    func testDepthPointsRejectUnknownConfidenceStaleFramesAndForeignSegmentsWithoutMutation() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        let badPoints = [point([0, 1, -2], confidence: 0), point([0, 1, -2], confidence: 3),
            point([0, 1, -2], depth: 0), point([0, 1, -2], depth: .nan),
            point([0, 1, -2], segment: "old-segment"), point([.nan, 1, -2]),
            SpatialPoint(world: [0, 1, -2], record: [:])]
        for bad in badPoints {
            XCTAssertThrowsError(try state.append(bad, tracking: "normal", frameAgeSeconds: 0))
            XCTAssertTrue(state.pending.isEmpty)
        }
        XCTAssertThrowsError(try state.append(point([0, 1, -2]), tracking: "limited", frameAgeSeconds: 0))
        XCTAssertThrowsError(try state.append(point([0, 1, -2]), tracking: "normal", frameAgeSeconds: 0.51))
        XCTAssertNil(try state.append(point([0, 1, -2], confidence: 1), tracking: "normal", frameAgeSeconds: 0.5))
        XCTAssertEqual(state.pending.count, 1)
    }

    func testCompletedVectorsRemainImmutableAcrossNewPairAndTagWidthWorkflow() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        let first = try completeDistance(&state)
        XCTAssertEqual(first.distanceMeters, 5, accuracy: 1e-6)
        XCTAssertNil(try state.append(point([10, 2, -4]), tracking: "normal", frameAgeSeconds: 0))
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.completed.count, 1)
        assertVector(state.completed[0].start, [0, 0, -2])
        assertVector(state.completed[0].end, [3, 4, -2])
        state.setMode(.tagWidth)
        XCTAssertNil(try state.append(point([0, 0, -1]), tracking: "normal", frameAgeSeconds: 0))
        XCTAssertNil(try state.append(point([0.1651, 0, -1]), tracking: "normal", frameAgeSeconds: 0))
        XCTAssertEqual(state.pending.count, 2)
        XCTAssertEqual(state.completed.map(\.id), [first.id])
        state.setMode(.distance)
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.completed.map(\.id), [first.id])
    }

    func testTransientTrackingClearAndExplicitClearHaveDifferentFloorLifetimeThanSegmentReset() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        try state.confirmFloor(plane(), tracking: "normal", frameAgeSeconds: 0)
        let saved = try completeDistance(&state)
        _ = try state.append(point([1, 1, -1]), tracking: "normal", frameAgeSeconds: 0)
        // Coordinator clears only pending points when tracking becomes limited.
        state.clearPending()
        XCTAssertThrowsError(try state.append(point([1, 1, -1]), tracking: "limited", frameAgeSeconds: 0))
        XCTAssertEqual(state.completed.map(\.id), [saved.id])
        XCTAssertNotNil(state.floor)
        state.setMode(.height)
        XCTAssertNotNil(try state.append(point([1, 2, -1]), tracking: "normal", frameAgeSeconds: 0))
        XCTAssertEqual(state.completed.count, 2)
        state.clearMeasurements()
        XCTAssertTrue(state.completed.isEmpty)
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertNotNil(state.floor)
        state.reset(segmentID: "segment-B")
        XCTAssertEqual(state.segmentID, "segment-B")
        XCTAssertNil(state.floor)
        XCTAssertTrue(state.completed.isEmpty)
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.mode, .selectFloor)
    }

    func testMeasurementCapRejectsWithoutDeletingExistingVectorsAndStillAllowsTagWidth() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A", maximumCount: 2)
        let a = try completeDistance(&state), b = try completeDistance(&state, offset: 10)
        XCTAssertThrowsError(try state.append(point([20, 0, -2]), tracking: "normal", frameAgeSeconds: 0))
        XCTAssertEqual(state.completed.map(\.id), [a.id, b.id])
        state.setMode(.tagWidth)
        XCTAssertNoThrow(try state.append(point([0, 0, -1]), tracking: "normal", frameAgeSeconds: 0))
        XCTAssertEqual(state.completed.map(\.id), [a.id, b.id])
    }

    func testHeightSnapshotSerializesFrozenFloorAndSourceProvenance() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        try state.confirmFloor(plane(normal: [-0.1, 1, -0.2]), tracking: "normal", frameAgeSeconds: 0)
        let measurement = try XCTUnwrap(state.append(point([2, 3, 4], frame: "target-frame"), tracking: "normal", frameAgeSeconds: 0))
        XCTAssertEqual(measurement.kind, "height")
        XCTAssertEqual(measurement.verticalMeters, 2, accuracy: 1e-5)
        XCTAssertEqual(measurement.horizontalMeters, 0, accuracy: 1e-5)
        let encoded = try JSONSerialization.data(withJSONObject: measurement.dictionary, options: [.sortedKeys])
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(decoded["segmentId"] as? String, "segment-A")
        XCTAssertEqual(decoded["timestamp"] as? Double, 11.5)
        let floor = try XCTUnwrap(decoded["floor"] as? [String: Any])
        XCTAssertEqual(floor["operatorConfirmed"] as? Bool, true)
        XCTAssertEqual(floor["frameId"] as? String, "floor-frame")
        XCTAssertEqual(floor["source"] as? String, "ARPlaneAnchor")
        let sources = try XCTUnwrap(decoded["sourcePoints"] as? [[String: Any]])
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources[0]["source"] as? String, "vertical-intersection-with-confirmed-floor")
        XCTAssertEqual(sources[0]["floorId"] as? String, "floor-A")
        XCTAssertEqual(sources[1]["source"] as? String, "sceneDepth")
        XCTAssertEqual(sources[1]["frameId"] as? String, "target-frame")
        XCTAssertEqual(sources[1]["confidence"] as? Int, 2)
        state.clearMeasurements()
        state.reset(segmentID: "segment-B")
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: measurement.dictionary, options: [.sortedKeys]), encoded)
    }
}
