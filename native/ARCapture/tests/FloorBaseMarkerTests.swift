import XCTest
import simd

final class FloorBaseMarkerTests: XCTestCase {
    private func floor(tiltDegrees: Float = 0, measured: Bool = true, origin: SIMD3<Float> = [2,-1,4], normal: SIMD3<Float>? = nil) -> SpatialPlane {
        let radians = tiltDegrees * .pi / 180
        let n = normal ?? SIMD3<Float>(sin(radians),cos(radians),0)
        return SpatialPlane(id: "floor", classification: "floor", origin: origin, normal: n,
            vertices: [origin+[-1,0,-1],origin+[1,0,-1],origin+[1,0,1],origin+[-1,0,1]],
            segmentID: "segment", frameID: "floor-frame", timestamp: 1,
            tiltSource: measured ? "sceneDepth-plane-fit" : "unavailable")
    }
    private func assertSquare(_ marker: FloorBaseMarker.Marker, datum: SpatialPlane, center: SIMD3<Float>, side: Float = 0.3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(marker.corners.count, 4, file: file,line: line)
        XCTAssertEqual(marker.center, center, file: file,line: line)
        let mean = marker.corners.reduce(SIMD3<Float>.zero,+)/4
        XCTAssertLessThan(simd_length(mean-center), 1e-5, file: file,line: line)
        let n = simd_normalize(datum.normal)
        for index in 0..<4 {
            XCTAssertEqual(simd_length(marker.corners[(index+1)%4]-marker.corners[index]), side, accuracy: 1e-5, file: file,line: line)
            XCTAssertEqual(simd_dot(n,marker.corners[index]-datum.origin), 0, accuracy: 1e-5, file: file,line: line)
        }
        XCTAssertEqual(simd_length(marker.corners[2]-marker.corners[0]), side*sqrt(2), accuracy: 1e-5, file: file,line: line)
    }
    func testDefaultThirtyCentimeterSquareIsCenteredAndCoplanar() throws {
        let datum = floor(), center = datum.origin+SIMD3<Float>(0.5,0,-0.25)
        let marker = try XCTUnwrap(FloorBaseMarker.make(center: center,floor: datum))
        assertSquare(marker,datum: datum,center: center)
        XCTAssertEqual(marker.sideMeters,0.30); XCTAssertEqual(marker.state,.level)
    }
    func testTiltedSquareUsesStableWorldBasisAndUpwardWinding() throws {
        let datum = floor(tiltDegrees: 5)
        let marker = try XCTUnwrap(FloorBaseMarker.make(center: datum.origin,floor: datum))
        assertSquare(marker,datum: datum,center: datum.origin)
        XCTAssertEqual(marker.state,.tilted)
        XCTAssertEqual(FloorBaseMarker.make(center: datum.origin,floor: datum)?.corners,marker.corners)
        let edgeA = marker.corners[1]-marker.corners[0], edgeB = marker.corners[2]-marker.corners[1]
        XCTAssertGreaterThan(simd_dot(simd_cross(edgeA,edgeB),datum.normal),0)
        XCTAssertNotEqual(marker.corners[0].y,marker.corners[1].y)
    }
    func testHalfDegreeBoundaryAndUnknownGeometryAreExplicit() throws {
        XCTAssertEqual(FloorBaseMarker.make(center: floor(tiltDegrees: 0.5).origin,floor: floor(tiltDegrees: 0.5))?.state,.level)
        XCTAssertEqual(FloorBaseMarker.make(center: floor(tiltDegrees: 0.51).origin,floor: floor(tiltDegrees: 0.51))?.state,.tilted)
        let unknown = floor(measured: false)
        XCTAssertNil(unknown.effectiveTiltDegrees)
        XCTAssertEqual(FloorBaseMarker.make(center: unknown.origin,floor: unknown)?.state,.unknown)
    }
    func testGravityLevelingUsesActivePlaneAndPreservesOriginalTilt() throws {
        let observed = floor(tiltDegrees: 5), leveled = SpatialMeasurementMath.effectiveFloor(observed,levelWithGravity: true)
        let marker = try XCTUnwrap(FloorBaseMarker.make(center: leveled.origin,floor: leveled))
        assertSquare(marker,datum: leveled,center: leveled.origin)
        XCTAssertEqual(marker.state,.level); XCTAssertEqual(leveled.observedTiltDegrees!,5,accuracy: 1e-5)
        XCTAssertTrue(marker.corners.allSatisfy { $0.y == leveled.origin.y })
        let unknownLeveled = SpatialMeasurementMath.effectiveFloor(floor(measured: false),levelWithGravity: true)
        XCTAssertEqual(FloorBaseMarker.make(center: unknownLeveled.origin,floor: unknownLeveled)?.state,.level)
    }
    func testInvalidCentersPlanesAndSidesFailClosed() {
        let datum = floor()
        XCTAssertNil(FloorBaseMarker.make(center: datum.origin+[0,0.001,0],floor: datum))
        XCTAssertNil(FloorBaseMarker.make(center: [.nan,0,0],floor: datum))
        for side in [0.0,-0.3,Double.nan,Double.infinity,Double.greatestFiniteMagnitude,1e30,Double.leastNonzeroMagnitude] {
            XCTAssertNil(FloorBaseMarker.make(center: datum.origin,floor: datum,sideMeters: side))
        }
        for invalid in [floor(normal: [0,0,0]),floor(normal: [1,0,0]),floor(normal: [.nan,1,0]),floor(origin: [.infinity,0,0])] {
            XCTAssertNil(FloorBaseMarker.make(center: datum.origin,floor: invalid))
        }
        let tooLarge = floor(origin: [1e20,0,1e20])
        XCTAssertNil(FloorBaseMarker.make(center: tooLarge.origin,floor: tooLarge))
    }
    func testAutomaticHeightVectorCarriesItsImmutableValidatedFloorSnapshot() throws {
        let datum = floor(tiltDegrees: 5), now = ProcessInfo.processInfo.systemUptime
        var basis = datum.dictionary; basis["operatorConfirmed"] = true
        let start = datum.origin, end = start+SIMD3<Float>(0,2,0)
        let row: [String: Any] = ["id": 4, "floorHeight": ["available": true,"meters": 2.0,"source": "sceneDepth",
            "floorId": datum.id,"frameId": "tag-frame","segmentId": "segment","timestamp": now,"floor": basis,
            "floorFootWorldMeters": SpatialMeasurementMath.array(start),"worldMeters": SpatialMeasurementMath.array(end)]]
        let vector = try XCTUnwrap(TagHeightVectors.make(from: [row],floor: datum,segmentID: "segment",frameID: "tag-frame",tracking: "normal",mode: .distance,now: now).first)
        let newDatum = SpatialMeasurementMath.effectiveFloor(datum,levelWithGravity: true)
        XCTAssertEqual(vector.floor.normal,datum.normal); XCTAssertFalse(vector.floor.levelFloorWithGravity)
        XCTAssertEqual(FloorBaseMarker.make(center: vector.start,floor: vector.floor)?.state,.tilted)
        XCTAssertTrue(TagHeightVectors.make(from: [row],floor: newDatum,segmentID: "segment",frameID: "tag-frame",tracking: "normal",mode: .distance,now: now).isEmpty)
    }
}
