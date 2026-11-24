import XCTest
import Foundation

final class TagPoseReadoutTests: XCTestCase {
    private let identity = [1.0,0,0, 0,1,0, 0,0,1]

    private func optical(_ translation: [Double] = [0.3,-0.4,2], rotation: [Double]? = nil) -> [String: Any] {
        ["translation": translation, "rotationRowMajor": rotation ?? identity]
    }
    private func assertNumbers(_ actual: [Double], _ expected: [Double], accuracy: Double = 1e-10,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a,b) in zip(actual,expected) { XCTAssertEqual(a,b,accuracy: accuracy,file: file,line: line) }
    }

    func testConventionLabelsAxesAndCodableNamesAreExplicit() throws {
        XCTAssertEqual(TagPoseConvention.allCases.map(\.rawValue),["rawOptical","ftcSdk","frcPhotonVision"])
        XCTAssertEqual(TagPoseConvention.allCases.map(\.label),["Raw optical","FTC SDK","FRC / PhotonVision"])
        XCTAssertEqual(TagPoseConvention.rawOptical.translationTitles,["X right · m","Y down · m","Z forward · m"])
        XCTAssertEqual(TagPoseConvention.ftcSdk.translationTitles,["X right · m","Y forward · m","Z up · m"])
        XCTAssertEqual(TagPoseConvention.frcPhotonVision.translationTitles,["X forward · m","Y left · m","Z up · m"])
        XCTAssertEqual(Set(TagPoseConvention.allCases.map(\.cameraFrame)).count,3)
        XCTAssertEqual(Set(TagPoseConvention.allCases.map(\.tagFrame)).count,3)
        for convention in TagPoseConvention.allCases {
            let data = try JSONEncoder().encode(convention)
            XCTAssertEqual(try JSONDecoder().decode(TagPoseConvention.self,from: data),convention)
        }
    }

    func testAllProfilesUseDistinctCameraAndTagBasesAndKeepThreeDimensionalDistance() throws {
        let raw = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(),convention: .rawOptical))
        let ftc = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(),convention: .ftcSdk))
        let frc = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(),convention: .frcPhotonVision))
        assertNumbers(raw.translationMeters,[0.3,-0.4,2])
        assertNumbers(ftc.translationMeters,[0.3,2,0.4])
        assertNumbers(frc.translationMeters,[2,-0.3,0.4])
        assertNumbers(raw.rotationRowMajor,identity)
        assertNumbers(ftc.rotationRowMajor,identity)
        assertNumbers(frc.rotationRowMajor,[-1,0,0, 0,-1,0, 0,0,1])
        assertNumbers(raw.rollPitchYawDegrees,[0,0,0])
        assertNumbers(ftc.rollPitchYawDegrees,[0,0,0])
        assertNumbers(frc.rollPitchYawDegrees,[0,0,180])
        for value in [raw,ftc,frc] {
            XCTAssertEqual(value.cameraDistanceMeters,2.0615528128088303,accuracy: 1e-12)
            XCTAssertFalse(value.eulerSingular)
            XCTAssertEqual(value.dictionary["reference"] as? String,"tag-relative-to-camera")
        }
        XCTAssertEqual(try XCTUnwrap(ftc.planarRangeMeters),2.0223748416156684,accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ftc.horizontalBearingDegrees),-8.530765609948133,accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ftc.elevationDegrees),11.309932474020215,accuracy: 1e-12)
        XCTAssertNil(raw.planarRangeMeters); XCTAssertNil(raw.horizontalBearingDegrees); XCTAssertNil(raw.elevationDegrees)
        XCTAssertNil(frc.planarRangeMeters); XCTAssertNil(frc.horizontalBearingDegrees); XCTAssertNil(frc.elevationDegrees)
    }

    func testFullMatrixWinsOverStaleLegacyEulerAndRangeWithoutChangingTheSourcePose() throws {
        let rotation = opticalXYZ(roll: 12,pitch: -28,yaw: 33)
        var source = optical(rotation: rotation)
        source["eulerDegrees"] = [999.0,999,999]
        source["rangeMeters"] = -123.0
        let original = try JSONSerialization.data(withJSONObject: source,options: [.sortedKeys])
        let raw = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: source,convention: .rawOptical))
        let frc = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: source,convention: .frcPhotonVision))
        assertNumbers(raw.rollPitchYawDegrees,[12,-28,33])
        assertNumbers(frc.rollPitchYawDegrees,[-32.08044893658773,25.11740293483954,-162.5252022088979])
        XCTAssertEqual(raw.cameraDistanceMeters,2.0615528128088303,accuracy: 1e-12)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: source,options: [.sortedKeys]),original)
        XCTAssertEqual(raw.displayRotationTitles,["Rot X · °","Rot Y · °","Rot Z · °"])
        XCTAssertEqual(frc.displayRotationTitles,["Roll · °","Pitch · °","Yaw · °"])
    }

    func testFTCStoresRPYButDisplaysSDKPitchRollYawAndPreservesAlternateEulerBranch() throws {
        let rotation = ftcMatrix(yaw: 20,pitch: 110,roll: -30)
        let value = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(rotation: rotation),convention: .ftcSdk))
        assertNumbers(value.rollPitchYawDegrees,[-30,110,19.999998092651367],accuracy: 1e-8)
        assertNumbers(value.displayRotationDegrees,[110,-30,19.999998092651367],accuracy: 1e-8)
        XCTAssertEqual(value.displayRotationTitles,["Pitch · °","Roll · °","Yaw · °"])
        let decoded = try XCTUnwrap(TagPoseReadout.decode(record: value.dictionary))
        assertNumbers(decoded.displayRotationDegrees,value.displayRotationDegrees)
    }

    func testSDKAndRawSingularitiesRemainExplicitAndRealZeroIsAvailable() throws {
        let ftc = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(rotation: ftcMatrix(yaw: 20,pitch: 89.999,roll: 30)),convention: .ftcSdk))
        XCTAssertTrue(ftc.eulerSingular)
        assertNumbers(ftc.rollPitchYawDegrees,[0,90,49.999996185302734],accuracy: 1e-8)
        XCTAssertNotNil(TagPoseReadout.decode(record: ftc.dictionary))
        let raw = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(rotation: opticalXYZ(roll: 20,pitch: 90,yaw: 35)),convention: .rawOptical))
        XCTAssertTrue(raw.eulerSingular)
        assertNumbers(raw.rollPitchYawDegrees,[0,90,15],accuracy: 1e-8)
        let zero = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical([0,0,2]),convention: .ftcSdk))
        XCTAssertEqual(zero.horizontalBearingDegrees,0)
        XCTAssertEqual(zero.elevationDegrees,0)
        XCTAssertEqual(zero.rollPitchYawDegrees,[0,0,0])
    }

    func testEveryProfileRoundTripsThroughJSONWithExplicitUnitsAndFrames() throws {
        for convention in TagPoseConvention.allCases {
            let value = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(rotation: opticalXYZ(roll: 12,pitch: -28,yaw: 33)),convention: convention))
            let json = try JSONSerialization.data(withJSONObject: value.dictionary)
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let decoded = try XCTUnwrap(TagPoseReadout.decode(record: record))
            XCTAssertEqual(decoded.convention,convention)
            assertNumbers(decoded.translationMeters,value.translationMeters)
            assertNumbers(decoded.rotationRowMajor,value.rotationRowMajor)
            assertNumbers(decoded.rollPitchYawDegrees,value.rollPitchYawDegrees)
            XCTAssertEqual(decoded.dictionary["units"] as? [String:String],["length":"meter","angle":"degree"])
            XCTAssertEqual(decoded.dictionary["cameraFrame"] as? String,convention.cameraFrame)
            XCTAssertEqual(decoded.dictionary["tagFrame"] as? String,convention.tagFrame)
            XCTAssertEqual(decoded.dictionary["rotationConvention"] as? String,convention.rotationConvention)
            XCTAssertEqual(decoded.dictionary["conventionVersion"] as? Int,1)
        }
    }

    func testInvalidOrMissingOpticalDataNeverFabricatesZeroReadouts() {
        let invalidTranslations: [Any] = [NSNull(),[],[0,0],[0,0,0],[0,0,-1],[true,0,2],[0,Double.nan,2],[0,0,Double.infinity],["0",0,2]]
        let invalidRotations: [Any] = [NSNull(),[],[1,0],[-1,0,0,0,1,0,0,0,1],[2,0,0,0,2,0,0,0,2],
                                       [true,0,0,0,1,0,0,0,1],[Double.nan,0,0,0,1,0,0,0,1],
                                       [1,0.2,0,0,1,0,0,0,1]]
        for convention in TagPoseConvention.allCases {
            XCTAssertNil(TagPoseReadout.evaluate(opticalPose: [:],convention: convention))
            for translation in invalidTranslations {
                XCTAssertNil(TagPoseReadout.evaluate(opticalPose: ["translation":translation,"rotationRowMajor":identity],convention: convention))
            }
            for rotation in invalidRotations {
                XCTAssertNil(TagPoseReadout.evaluate(opticalPose: ["translation":[0,0,2],"rotationRowMajor":rotation],convention: convention))
            }
        }
    }

    func testDecodeRejectsWrongMetadataAndInconsistentNumbers() throws {
        let good = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(),convention: .frcPhotonVision)).dictionary
        let changes: [(String,Any)] = [
            ("convention","first"),("conventionVersion",2),("conventionVersion",true),
            ("reference","camera-relative-to-tag"),("cameraFrame",TagPoseConvention.ftcSdk.cameraFrame),
            ("tagFrame",TagPoseConvention.rawOptical.tagFrame),("matrixOrder","column-major"),
            ("rotationConvention",TagPoseConvention.rawOptical.rotationConvention),
            ("units",["length":"inch","angle":"degree"]),("units",["length":"meter","angle":"radian"]),
            ("translationMeters",[2,-0.3]),("translationMeters",[true,-0.3,0.4]),
            ("translationMeters",[-2,-0.3,0.4]),("rotationRowMajor",identity),
            ("rollPitchYawDegrees",[0,0,0]),("cameraDistanceMeters",99),
            ("cameraDistanceMeters",0),("cameraDistanceMeters",Double.nan),
            ("eulerSingular",1),("eulerSingular",true),("horizontalBearingDegrees",0)
        ]
        for (key,value) in changes {
            var record = good; record[key] = value
            XCTAssertNil(TagPoseReadout.decode(record: record),"Unexpectedly accepted \(key)=\(value)")
        }
        for key in ["convention","conventionVersion","reference","cameraFrame","tagFrame","rotationConvention","matrixOrder","units",
                    "translationMeters","rotationRowMajor","rollPitchYawDegrees","cameraDistanceMeters","eulerSingular"] {
            var record = good; record.removeValue(forKey: key)
            XCTAssertNil(TagPoseReadout.decode(record: record),"Missing \(key) must not become a zero/default")
        }
        let ftc = try XCTUnwrap(TagPoseReadout.evaluate(opticalPose: optical(),convention: .ftcSdk)).dictionary
        for key in ["planarRangeMeters","horizontalBearingDegrees","elevationDegrees"] {
            for invalid: Any in [NSNull(),true,Double.nan,999.0] {
                var record = ftc; record[key] = invalid
                XCTAssertNil(TagPoseReadout.decode(record: record))
            }
            var record = ftc; record.removeValue(forKey: key)
            XCTAssertNil(TagPoseReadout.decode(record: record))
        }
    }

    private func multiply(_ a: [Double],_ b: [Double]) -> [Double] {
        var result = Array(repeating: 0.0,count: 9)
        for r in 0..<3 { for c in 0..<3 { for k in 0..<3 { result[3*r+c] += a[3*r+k] * b[3*k+c] } } }
        return result
    }
    private func axis(_ index: Int,_ degrees: Double) -> [Double] {
        var value = identity
        let c = cos(degrees * .pi / 180),s = sin(degrees * .pi / 180),a = (index+1)%3,b = (index+2)%3
        value[3*a+a] = c; value[3*a+b] = -s; value[3*b+a] = s; value[3*b+b] = c
        return value
    }
    private func ftcMatrix(yaw: Double,pitch: Double,roll: Double) -> [Double] {
        multiply(multiply(axis(1,-yaw),axis(0,pitch)),axis(2,roll))
    }
    private func opticalXYZ(roll: Double,pitch: Double,yaw: Double) -> [Double] {
        multiply(multiply(axis(2,yaw),axis(1,pitch)),axis(0,roll))
    }
}
