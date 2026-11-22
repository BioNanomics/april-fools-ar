import XCTest
import simd

final class FloorPlaneFitTests: XCTestCase {
    private func cloud(degrees: Double = 0, reference: SIMD3<Float> = [0, 1.7, 0], zSlope: Double = 0,
                       count: Int = 12, narrow: Bool = false) -> [SIMD3<Float>] {
        let slope = tan(degrees * .pi / 180)
        return (0..<count*count).map { index in
            let x = Double(index % count)/Double(count-1)*2-1
            let z = (Double(index/count)/Double(count-1)*2-1) * (narrow ? 0.01 : 1)
            return reference + SIMD3<Float>(Float(x), Float(slope*x+zSlope*z), Float(z))
        }
    }

    func testKnownTwoAndFiveDegreePlanesProduceObservedUpwardNormals() throws {
        for degrees in [2.0, 5.0] {
            let result = try XCTUnwrap(FloorPlaneFit.fit(points: cloud(degrees: degrees), referenceXZ: [0, 0]))
            XCTAssertEqual(result.tiltDegrees, degrees, accuracy: 0.0001)
            XCTAssertEqual(Double(result.origin.y), 1.7, accuracy: 1e-6)
            XCTAssertEqual(Double(result.normal.x), -sin(degrees * .pi/180), accuracy: 1e-6)
            XCTAssertEqual(Double(result.normal.y), cos(degrees * .pi/180), accuracy: 1e-6)
            XCTAssertEqual(result.sampleCount, 144)
            XCTAssertEqual(result.inlierCount, 144)
            XCTAssertLessThan(result.rmsMeters, 1e-6)
        }
    }

    func testTranslatedCoordinatesAndTwoAxisSlopeKeepTheRequestedOrigin() throws {
        let reference = SIMD3<Float>(1000, 7.25, -2000), zSlope = tan(2.0 * .pi/180)
        let result = try XCTUnwrap(FloorPlaneFit.fit(points: cloud(degrees: 3, reference: reference, zSlope: zSlope), referenceXZ: [reference.x, reference.z]))
        XCTAssertEqual(result.origin.x, reference.x)
        XCTAssertEqual(result.origin.z, reference.z)
        XCTAssertEqual(result.origin.y, reference.y, accuracy: 0.001)
        XCTAssertEqual(result.tiltDegrees, atan(hypot(tan(3.0 * .pi/180), zSlope))*180 / .pi, accuracy: 0.01)
        XCTAssertLessThan(result.rmsMeters, 0.001)
        XCTAssertTrue(result.normal.y > 0)
    }

    func testFlatObservedCloudHasAValidZeroTilt() throws {
        let result = try XCTUnwrap(FloorPlaneFit.fit(points: cloud(), referenceXZ: [0.25, -0.25]))
        XCTAssertEqual(result.tiltDegrees, 0, accuracy: 1e-10)
        XCTAssertEqual(result.normal, SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(result.origin.y, 1.7, accuracy: 1e-6)
    }

    func testNoiseAndMinorityOutliersAreRobustAndDeterministic() throws {
        var points = cloud(degrees: 4)
        for index in points.indices {
            points[index].y += index % 5 == 0 ? 0.22 : Float(sin(Double(index)*1.7)*0.006)
        }
        let result = try XCTUnwrap(FloorPlaneFit.fit(points: points, referenceXZ: [0, 0]))
        let replay = try XCTUnwrap(FloorPlaneFit.fit(points: points, referenceXZ: [0, 0]))
        XCTAssertEqual(result.tiltDegrees, 4, accuracy: 0.15)
        XCTAssertEqual(result.origin.y, 1.7, accuracy: 0.005)
        XCTAssertGreaterThanOrEqual(result.inlierCount, 110)
        XCTAssertLessThan(result.inlierCount, result.sampleCount)
        XCTAssertLessThan(result.rmsMeters, 0.01)
        XCTAssertEqual(result.normal, replay.normal)
        XCTAssertEqual(result.origin, replay.origin)
        XCTAssertEqual(result.inlierCount, replay.inlierCount)
    }

    func testInsufficientNonfiniteLineAndNarrowCloudsRemainUnknown() {
        let valid = cloud()
        XCTAssertNil(FloorPlaneFit.fit(points: Array(valid.prefix(31)), referenceXZ: [0, 0]))
        XCTAssertNil(FloorPlaneFit.fit(points: Array(repeating: SIMD3<Float>(0, 0, 0), count: 513), referenceXZ: [0, 0]))
        var invalid = valid; invalid[10].y = .nan
        XCTAssertNil(FloorPlaneFit.fit(points: invalid, referenceXZ: [0, 0]))
        XCTAssertNil(FloorPlaneFit.fit(points: valid, referenceXZ: [.infinity, 0]))
        let line = (0..<64).map { SIMD3<Float>(Float($0)/32, 1, Float($0)/16) }
        XCTAssertNil(FloorPlaneFit.fit(points: line, referenceXZ: [0, 0]))
        XCTAssertNil(FloorPlaneFit.fit(points: cloud(narrow: true), referenceXZ: [0, 0]))
        let twentyCentimeterPatch = valid.map { SIMD3<Float>($0.x, $0.y, $0.z*0.1) }
        XCTAssertNil(FloorPlaneFit.fit(points: twentyCentimeterPatch, referenceXZ: [0, 0]))
    }

    func testSteepAndMostlyInconsistentPointsDoNotBecomeFloorTilt() {
        XCTAssertNil(FloorPlaneFit.fit(points: cloud(degrees: 30), referenceXZ: [0, 0]))
        var inconsistent = cloud(degrees: 2)
        for index in inconsistent.indices where index % 3 != 0 {
            inconsistent[index].y += Float(index % 11-5)*0.15
        }
        XCTAssertNil(FloorPlaneFit.fit(points: inconsistent, referenceXZ: [0, 0]))
    }
}
