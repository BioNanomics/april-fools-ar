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
    private func finishFloor(_ state: inout SpatialMeasurementState, plane supplied: SpatialPlane? = nil,
                             requested: SpatialMode = .distance) throws {
        let selected = supplied ?? plane()
        state.setMode(requested)
        state.updateCandidates([selected])
        try state.selectFloorCandidate(selected, tracking: "normal", frameAgeSeconds: 0)
        try state.completeFloorSetup(expectedCandidateID: selected.id, tracking: "normal", frameAgeSeconds: 0)
    }
    private func rectangle(_ width: Float, _ depth: Float, rotation: Float = 0, id: String = "floor-A",
                           classification: String = "floor", segment: String = "segment-A", y: Float = 0) -> SpatialPlane {
        let vertices: [SIMD3<Float>] = [[-width/2, y, -depth/2], [width/2, y, -depth/2], [width/2, y, depth/2], [-width/2, y, depth/2]]
        return SpatialPlane(id: id, classification: classification, origin: [0, y, 0], normal: [0, 1, 0],
            vertices: vertices.map { [cos(rotation)*$0.x-sin(rotation)*$0.z, y, sin(rotation)*$0.x+cos(rotation)*$0.z] },
            segmentID: segment, frameID: "floor-frame", timestamp: 10)
    }
    private func completeDistance(_ state: inout SpatialMeasurementState, offset: Float = 0) throws -> SpatialMeasurement {
        if state.floor == nil { try finishFloor(&state) }
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
        state.updateCandidates([plane()])
        for tracking in ["limited", "unavailable"] {
            XCTAssertThrowsError(try state.selectFloorCandidate(plane(), tracking: tracking, frameAgeSeconds: 0))
        }
        for age in [-0.01, 0.501, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try state.completeFloorSetup(expectedCandidateID: "floor-A", tracking: "normal", frameAgeSeconds: age))
        }
        for rejected in [plane(segment: "old-segment"), plane(classification: "wall"), plane(classification: "table")] {
            state.updateCandidates([rejected])
            XCTAssertThrowsError(try state.selectFloorCandidate(rejected, tracking: "normal", frameAgeSeconds: 0))
            XCTAssertThrowsError(try state.completeFloorSetup(expectedCandidateID: rejected.id, tracking: "normal", frameAgeSeconds: 0))
        }
        XCTAssertNil(state.floor)
        let selected = plane(classification: "unclassified")
        state.updateCandidates([selected])
        try state.selectFloorCandidate(selected, tracking: "normal", frameAgeSeconds: 0.5)
        XCTAssertNil(state.floor,"A candidate tap cannot confirm the floor")
        try state.completeFloorSetup(expectedCandidateID: selected.id, tracking: "normal", frameAgeSeconds: 0.5)
        XCTAssertEqual(state.mode, .height)
        XCTAssertEqual(state.floor?.id, "floor-A")
    }

    func testDepthPointsRejectUnknownConfidenceStaleFramesAndForeignSegmentsWithoutMutation() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        try finishFloor(&state)
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
        try finishFloor(&state, requested: .height)
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
        try finishFloor(&state, plane: plane(normal: [-0.1, 1, -0.2]), requested: .height)
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

    func testEveryManualModeRequiresDoneEvenAfterAValidCandidateTap() throws {
        for requested in [SpatialMode.distance, .height, .tagWidth] {
            var state = SpatialMeasurementState(segmentID: "segment-A")
            state.setMode(requested)
            XCTAssertEqual(state.mode, .selectFloor)
            XCTAssertEqual(state.requestedMode, requested)
            XCTAssertThrowsError(try state.append(point([0, 1, -2]), tracking: "normal", frameAgeSeconds: 0))
            state.updateCandidates([plane()])
            try state.selectFloorCandidate(plane(), tracking: "normal", frameAgeSeconds: 0)
            XCTAssertNil(state.floor)
            XCTAssertTrue(state.pending.isEmpty)
            XCTAssertThrowsError(try state.append(point([0, 1, -2]), tracking: "normal", frameAgeSeconds: 0))
            try state.completeFloorSetup(expectedCandidateID: "floor-A", tracking: "normal", frameAgeSeconds: 0)
            XCTAssertEqual(state.mode, requested)
            XCTAssertNotNil(state.floor)
            XCTAssertNoThrow(try state.append(point([0, 1, -2]), tracking: "normal", frameAgeSeconds: 0))
        }
    }

    func testCoverageRejectsSmallAreaAndRotatedNarrowStripsButAcceptsExactBoundary() throws {
        for (candidate, reason) in [(rectangle(0.9, 0.9), "insufficientArea"),
            (rectangle(0.4, 3), "insufficientSpan"), (rectangle(0.1, 10, rotation: .pi/4), "insufficientSpan")] {
            var state = SpatialMeasurementState(segmentID: "segment-A")
            state.updateCandidates([candidate])
            XCTAssertEqual(state.floorSetupStatus(tracking: "normal", frameAgeSeconds: 0)["reason"] as? String, reason)
            XCTAssertThrowsError(try state.completeFloorSetup(expectedCandidateID: candidate.id, tracking: "normal", frameAgeSeconds: 0))
            XCTAssertNil(state.floor)
        }
        let rotated = SpatialMeasurementMath.floorCoverage(rectangle(0.1, 10, rotation: .pi/4))
        XCTAssertEqual(rotated.areaSquareMeters, 1, accuracy: 1e-5)
        XCTAssertEqual(rotated.minSpanMeters, 0.1, accuracy: 1e-5)
        var state = SpatialMeasurementState(segmentID: "segment-A")
        let exact = rectangle(0.5, 2)
        state.updateCandidates([exact])
        XCTAssertEqual(state.floorSetupStatus(tracking: "normal", frameAgeSeconds: 0)["ready"] as? Bool, true)
        try state.completeFloorSetup(expectedCandidateID: exact.id, tracking: "normal", frameAgeSeconds: 0)
        XCTAssertNotNil(state.floor)
    }

    func testCandidateGeometryRefinesUntilDoneThenTheConfirmedSnapshotIsImmutable() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        state.setMode(.height)
        state.updateCandidates([rectangle(0.5, 0.5)])
        XCTAssertNil(state.floor)
        XCTAssertEqual(state.floorSetupStatus(tracking: "normal", frameAgeSeconds: 0)["ready"] as? Bool, false)
        let refined = rectangle(2, 2)
        state.updateCandidates([refined])
        XCTAssertEqual(state.candidate?.vertices.count, 4)
        XCTAssertEqual(state.floorSetupStatus(tracking: "normal", frameAgeSeconds: 0)["areaSquareMeters"] as? Double, 4)
        try state.completeFloorSetup(expectedCandidateID: refined.id, tracking: "normal", frameAgeSeconds: 0)
        let frozen = try JSONSerialization.data(withJSONObject: XCTUnwrap(state.floor).dictionary, options: [.sortedKeys])
        state.updateCandidates([rectangle(4, 4, y: 0.3)])
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: XCTUnwrap(state.floor).dictionary, options: [.sortedKeys]), frozen)
        XCTAssertEqual(state.mode, .height)
        state.setMode(.distance)
        XCTAssertEqual(state.mode, .distance,"A completed floor is reused without scanning again")
        state.setMode(.selectFloor)
        XCTAssertThrowsError(try state.append(point([0, 1, -2]), tracking: "normal", frameAgeSeconds: 0),
            "Rescanning cannot create endpoints even while an older confirmed floor exists")
    }

    func testAutomaticSelectionIsStableAndManualUnclassifiedSelectionNeverSilentlySwitches() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        let small = rectangle(1, 1, id: "small"), large = rectangle(2, 2, id: "large")
        let unclassified = rectangle(3, 3, id: "manual", classification: "unclassified")
        state.updateCandidates([small, large, unclassified])
        XCTAssertEqual(state.candidate?.id, "large")
        XCTAssertEqual(state.candidateSelectionSource, "automatic")
        state.updateCandidates([rectangle(4, 4, id: "small"), large, unclassified])
        XCTAssertEqual(state.candidate?.id, "large","An automatically selected current ID must not bounce as other planes grow")
        try state.selectFloorCandidate(unclassified, tracking: "normal", frameAgeSeconds: 0)
        XCTAssertEqual(state.candidate?.id, "manual")
        XCTAssertEqual(state.candidateSelectionSource, "manual")
        state.updateCandidates([small, large])
        XCTAssertNil(state.candidate,"A lost manual choice cannot silently become a different floor")
        XCTAssertThrowsError(try state.completeFloorSetup(expectedCandidateID: "manual", tracking: "normal", frameAgeSeconds: 0))
        var fallback = SpatialMeasurementState(segmentID: "segment-A")
        fallback.updateCandidates([unclassified])
        XCTAssertNil(fallback.candidate,"Unclassified surfaces need an explicit tap")
    }

    func testDoneRejectsChangedCandidateIDLostCandidateAndLimitedTracking() throws {
        var state = SpatialMeasurementState(segmentID: "segment-A")
        let first = rectangle(2, 2, id: "first"), next = rectangle(3, 3, id: "next")
        state.updateCandidates([first])
        state.updateCandidates([next])
        XCTAssertEqual(state.candidate?.id, "next")
        XCTAssertThrowsError(try state.completeFloorSetup(expectedCandidateID: "first", tracking: "normal", frameAgeSeconds: 0))
        XCTAssertEqual(state.floorSetupStatus(tracking: "limited", frameAgeSeconds: 0)["ready"] as? Bool, false)
        XCTAssertThrowsError(try state.completeFloorSetup(expectedCandidateID: "next", tracking: "limited", frameAgeSeconds: 0))
        XCTAssertNil(state.floor)
        state.updateCandidates([])
        XCTAssertThrowsError(try state.completeFloorSetup(expectedCandidateID: "next", tracking: "normal", frameAgeSeconds: 0))
        state.reset(segmentID: "segment-B")
        state.updateCandidates([next])
        XCTAssertNil(state.candidate)
        XCTAssertNil(state.floor)
        XCTAssertEqual(state.mode, .selectFloor)
    }
}
