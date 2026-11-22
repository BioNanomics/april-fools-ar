import XCTest
import simd

final class FloorLevelingTests: XCTestCase {
    private func observedFloor(source: String = "sceneDepth-plane-fit") -> SpatialPlane {
        let normal = simd_normalize(SIMD3<Float>(-0.05, 1, -0.02))
        let vertices: [SIMD3<Float>] = [[-1, 0.93, -1], [1, 1.03, -1], [1, 1.07, 1], [-1, 0.97, 1]]
        return SpatialPlane(id: "floor", classification: "floor", origin: [0, 1, 0], normal: normal, vertices: vertices,
            segmentID: "segment", frameID: "floor-frame", timestamp: 10, tiltSource: source,
            floorFit: source == "sceneDepth-plane-fit" ? ["sampleCount": 144, "inlierCount": 128, "rmsMeters": 0.005, "frameId": "fit-frame", "timestamp": 9.9] : nil)
    }
    private func confirmedState(level: Bool = false) throws -> SpatialMeasurementState {
        var state = SpatialMeasurementState(segmentID: "segment", levelFloorWithGravity: level)
        state.setMode(.height)
        state.updateCandidates([observedFloor()])
        try state.completeFloorSetup(expectedCandidateID: "floor", tracking: "normal", frameAgeSeconds: 0.01)
        return state
    }
    private var target: SpatialPoint {
        SpatialPoint(world: [1, 2, 0], record: ["source": "sceneDepth", "segmentId": "segment", "frameId": "target-frame",
            "timestamp": 11.0, "confidence": 2, "depthMeters": 2.0])
    }

    func testObservedTiltRequiresDepthFitProvenanceAndKeepsFitEvidence() throws {
        let observed = observedFloor()
        XCTAssertEqual(try XCTUnwrap(observed.observedTiltDegrees), atan(hypot(0.05, 0.02))*180 / .pi, accuracy: 1e-5)
        XCTAssertEqual(observed.dictionary["tiltAvailable"] as? Bool, true)
        XCTAssertEqual((observed.dictionary["floorFit"] as? [String: Any])?["frameId"] as? String, "fit-frame")
        let rawAnchor = observedFloor(source: "unavailable")
        XCTAssertNil(rawAnchor.observedTiltDegrees)
        XCTAssertTrue(rawAnchor.dictionary["observedTiltDegrees"] is NSNull)
        XCTAssertEqual(rawAnchor.dictionary["tiltAvailable"] as? Bool, false)
        XCTAssertNil(rawAnchor.floorFit)
    }

    func testLevelingUsesConfirmedOriginHeightAndPreservesObservedGeometryEvidence() throws {
        let observed = observedFloor()
        let effective = SpatialMeasurementMath.effectiveFloor(observed, levelWithGravity: true)
        XCTAssertEqual(effective.origin, observed.origin)
        XCTAssertEqual(effective.normal, SIMD3<Float>(0, 1, 0))
        XCTAssertTrue(effective.vertices.allSatisfy { $0.y == observed.origin.y })
        XCTAssertEqual(effective.vertices.map(\.x), observed.vertices.map(\.x))
        XCTAssertEqual(effective.vertices.map(\.z), observed.vertices.map(\.z))
        XCTAssertEqual(effective.observedNormal, observed.normal)
        XCTAssertEqual(effective.observedTiltDegrees, observed.observedTiltDegrees)
        XCTAssertEqual(effective.effectiveTiltDegrees, 0)
        XCTAssertEqual(effective.floorFit?["inlierCount"] as? Int, 128)
        XCTAssertNotEqual(observed.vertices[0].y, effective.vertices[0].y, "Do not mutate the saved observed boundary")
    }

    func testInitialSavedLevelingFlagAppliesAsSoonAsFloorIsConfirmed() throws {
        let state = try confirmedState(level: true)
        XCTAssertTrue(state.levelFloorWithGravity)
        XCTAssertTrue(try XCTUnwrap(state.floor).levelFloorWithGravity)
        XCTAssertEqual(state.floor?.normal, SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(state.observedFloor?.normal, observedFloor().normal)
    }

    func testToggleImmediatelyChangesNewHeightBasisWithoutRewritingCompletedMeasurements() throws {
        var state = try confirmedState()
        let before = try XCTUnwrap(state.append(target, tracking: "normal", frameAgeSeconds: 0.01))
        XCTAssertEqual(before.verticalMeters, 0.95, accuracy: 1e-5)
        XCTAssertEqual(before.floor?.levelFloorWithGravity, false)
        state.setFloorLeveling(true)
        let after = try XCTUnwrap(state.append(target, tracking: "normal", frameAgeSeconds: 0.01))
        XCTAssertEqual(after.verticalMeters, 1, accuracy: 1e-5)
        XCTAssertEqual(after.floor?.levelFloorWithGravity, true)
        XCTAssertEqual(state.completed[0].floor?.normal, before.floor?.normal)
        XCTAssertEqual(state.completed[0].verticalMeters, before.verticalMeters)
        state.setFloorLeveling(false)
        XCTAssertEqual(state.floor?.normal, state.observedFloor?.normal)
        XCTAssertEqual(state.floor?.origin, state.observedFloor?.origin)
        XCTAssertEqual(state.floor?.vertices, state.observedFloor?.vertices)
        XCTAssertEqual(state.completed[1].floor?.normal, SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(state.completed[1].verticalMeters, after.verticalMeters)
    }
}
