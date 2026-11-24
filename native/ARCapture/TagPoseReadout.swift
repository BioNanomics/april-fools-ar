import Foundation
import CoreFoundation

/// An explicit camera-pose presentation profile, independent of tag-size mode,
/// competition identity, robot mounting extrinsics and the field coordinate frame.
enum TagPoseConvention: String, CaseIterable, Codable {
    case rawOptical, ftcSdk, frcPhotonVision

    var label: String {
        switch self {
        case .rawOptical: return "Raw optical"
        case .ftcSdk: return "FTC SDK"
        case .frcPhotonVision: return "FRC / PhotonVision"
        }
    }
    var cameraFrame: String {
        switch self {
        case .rawOptical: return "camera-optical-x-right-y-down-z-forward"
        case .ftcSdk: return "ftc-sdk-camera-x-right-y-forward-z-up"
        case .frcPhotonVision: return "frc-photonvision-camera-x-forward-y-left-z-up"
        }
    }
    var tagFrame: String {
        switch self {
        case .rawOptical: return "apriltag-tag-x-right-y-down-z-into-tag"
        case .ftcSdk: return "ftc-sdk-tag-x-right-y-into-tag-z-up"
        case .frcPhotonVision: return "photonvision-tag-x-out-y-printed-right-z-up"
        }
    }
    var rotationConvention: String {
        switch self {
        case .rawOptical:
            return "optical extrinsic XYZ; R=Rz(rotZ)*Ry(rotY)*Rx(rotX)"
        case .ftcSdk:
            return "FTC SDK intrinsic YXZ of raw optical R; yaw=-first,pitch=second,roll=third; float normalized minimum-magnitude Euler set"
        case .frcPhotonVision:
            return "PhotonVision NWU camera-to-target; R=B*Ropt*Ry(pi)*B^-1; extrinsic XYZ roll,pitch,yaw"
        }
    }
    var translationTitles: [String] {
        switch self {
        case .rawOptical: return ["X right · m", "Y down · m", "Z forward · m"]
        case .ftcSdk: return ["X right · m", "Y forward · m", "Z up · m"]
        case .frcPhotonVision: return ["X forward · m", "Y left · m", "Z up · m"]
        }
    }
}

/// Derived presentation only. Legacy optical pose/depth fields remain unchanged.
/// Decoding a saved derived record validates its metadata and numerical meaning;
/// old captures without this object can still be evaluated from their raw pose.
struct TagPoseReadout {
    static let conventionVersion = 1
    static let reference = "tag-relative-to-camera"
    static let units = ["length": "meter", "angle": "degree"]

    let convention: TagPoseConvention
    let translationMeters: [Double]
    /// Always [roll,pitch,yaw], including FTC's differently ordered UI row.
    let rollPitchYawDegrees: [Double]
    let rotationRowMajor: [Double]
    let cameraDistanceMeters: Double
    let planarRangeMeters: Double?
    let horizontalBearingDegrees: Double?
    let elevationDegrees: Double?
    let eulerSingular: Bool

    var displayRotationDegrees: [Double] {
        convention == .ftcSdk
            ? [rollPitchYawDegrees[1], rollPitchYawDegrees[0], rollPitchYawDegrees[2]]
            : rollPitchYawDegrees
    }
    var displayRotationTitles: [String] {
        switch convention {
        case .rawOptical: return ["Rot X · °", "Rot Y · °", "Rot Z · °"]
        case .ftcSdk: return ["Pitch · °", "Roll · °", "Yaw · °"]
        case .frcPhotonVision: return ["Roll · °", "Pitch · °", "Yaw · °"]
        }
    }
    var dictionary: [String: Any] {
        var record: [String: Any] = [
            "convention": convention.rawValue, "conventionVersion": Self.conventionVersion,
            "reference": Self.reference, "cameraFrame": convention.cameraFrame,
            "tagFrame": convention.tagFrame, "rotationConvention": convention.rotationConvention,
            "units": Self.units, "matrixOrder": "row-major",
            "translationMeters": translationMeters, "rollPitchYawDegrees": rollPitchYawDegrees,
            "rotationRowMajor": rotationRowMajor, "cameraDistanceMeters": cameraDistanceMeters,
            "eulerSingular": eulerSingular
        ]
        if let planarRangeMeters { record["planarRangeMeters"] = planarRangeMeters }
        if let horizontalBearingDegrees { record["horizontalBearingDegrees"] = horizontalBearingDegrees }
        if let elevationDegrees { record["elevationDegrees"] = elevationDegrees }
        return record
    }

    static func evaluate(opticalPose: [String: Any], convention: TagPoseConvention) -> Self? {
        guard let translation = numbers(opticalPose["translation"], count: 3),
              let rotation = numbers(opticalPose["rotationRowMajor"], count: 9) else { return nil }
        // This additive C API checks finite, positive optical depth and a proper
        // rotation. Cached legacy Euler/range fields are deliberately not used.
        var frc = AFTagFRCPose()
        let valid = translation.withUnsafeBufferPointer { t in
            rotation.withUnsafeBufferPointer { r in AFTagConvertOpticalPoseToFRC(t.baseAddress, r.baseAddress, &frc) }
        }
        guard valid != 0 else { return nil }
        switch convention {
        case .frcPhotonVision:
            return Self(convention: convention, translationMeters: tupleValues(frc.translationMeters),
                        rollPitchYawDegrees: [frc.rollDegrees, frc.pitchDegrees, frc.yawDegrees],
                        rotationRowMajor: tupleValues(frc.rotationRowMajor), cameraDistanceMeters: frc.euclideanRangeMeters,
                        planarRangeMeters: nil, horizontalBearingDegrees: nil, elevationDegrees: nil,
                        eulerSingular: frc.eulerSingular != 0)
        case .ftcSdk:
            var ftc = AFTagFTCPose()
            let converted = translation.withUnsafeBufferPointer { t in
                rotation.withUnsafeBufferPointer { r in AFTagConvertOpticalPoseToFTC(t.baseAddress, r.baseAddress, &ftc) }
            }
            guard converted != 0 else { return nil }
            return Self(convention: convention, translationMeters: tupleValues(ftc.translationMeters),
                        rollPitchYawDegrees: [ftc.rollDegrees, ftc.pitchDegrees, ftc.yawDegrees],
                        rotationRowMajor: tupleValues(ftc.rotationRowMajor), cameraDistanceMeters: frc.euclideanRangeMeters,
                        planarRangeMeters: ftc.planarRangeMeters, horizontalBearingDegrees: ftc.bearingDegrees,
                        elevationDegrees: ftc.elevationDegrees, eulerSingular: ftc.eulerSingular != 0)
        case .rawOptical:
            let cosinePitch = hypot(rotation[0], rotation[3])
            let singular = cosinePitch < 1e-8
            let roll = singular ? 0 : atan2(rotation[7], rotation[8])
            let pitch = atan2(-rotation[6], cosinePitch)
            let yaw = singular ? atan2(-rotation[1], rotation[4]) : atan2(rotation[3], rotation[0])
            return Self(convention: convention, translationMeters: translation,
                        rollPitchYawDegrees: [roll, pitch, yaw].map { $0 * 180 / .pi },
                        rotationRowMajor: rotation, cameraDistanceMeters: frc.euclideanRangeMeters,
                        planarRangeMeters: nil, horizontalBearingDegrees: nil, elevationDegrees: nil,
                        eulerSingular: singular)
        }
    }

    static func decode(record: [String: Any]) -> Self? {
        guard let raw = record["convention"] as? String, let convention = TagPoseConvention(rawValue: raw),
              number(record["conventionVersion"]) == Double(conventionVersion),
              record["reference"] as? String == reference,
              record["cameraFrame"] as? String == convention.cameraFrame,
              record["tagFrame"] as? String == convention.tagFrame,
              record["rotationConvention"] as? String == convention.rotationConvention,
              record["matrixOrder"] as? String == "row-major",
              let units = record["units"] as? [String: String], units["length"] == "meter", units["angle"] == "degree",
              let translation = numbers(record["translationMeters"], count: 3),
              let rotation = numbers(record["rotationRowMajor"], count: 9),
              let angles = numbers(record["rollPitchYawDegrees"], count: 3),
              let distance = number(record["cameraDistanceMeters"]), distance > 0,
              let singular = boolean(record["eulerSingular"]) else { return nil }
        let rawTranslation: [Double], rawRotation: [Double]
        switch convention {
        case .rawOptical:
            rawTranslation = translation; rawRotation = rotation
        case .ftcSdk:
            rawTranslation = [translation[0], -translation[2], translation[1]]
            let c = [1.0,0,0, 0,0,1, 0,-1,0], inverse = [1.0,0,0, 0,0,-1, 0,1,0]
            rawRotation = multiply(multiply(inverse, rotation), c)
        case .frcPhotonVision:
            rawTranslation = [-translation[1], -translation[2], translation[0]]
            let b = [0.0,0,1, -1,0,0, 0,-1,0], inverse = [0.0,-1,0, 0,0,-1, 1,0,0]
            let correction = [-1.0,0,0, 0,1,0, 0,0,-1]
            rawRotation = multiply(multiply(multiply(inverse, rotation), b), correction)
        }
        guard let canonical = evaluate(opticalPose: ["translation": rawTranslation, "rotationRowMajor": rawRotation], convention: convention),
              matches(distance, canonical.cameraDistanceMeters),
              zip(angles, canonical.rollPitchYawDegrees).allSatisfy({ matches($0.0, $0.1) }),
              singular == canonical.eulerSingular else { return nil }
        for (key, expected) in [("planarRangeMeters", canonical.planarRangeMeters),
                                ("horizontalBearingDegrees", canonical.horizontalBearingDegrees),
                                ("elevationDegrees", canonical.elevationDegrees)] {
            if let expected {
                guard let value = number(record[key]), matches(value, expected) else { return nil }
            } else if let value = record[key], !(value is NSNull) { return nil }
        }
        return canonical
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private static func numbers(_ value: Any?, count: Int) -> [Double]? {
        guard let values = value as? [Any], values.count == count else { return nil }
        let result = values.compactMap(number)
        return result.count == count ? result : nil
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private static func tupleValues<T>(_ tuple: T) -> [Double] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Double.self)) }
    }
    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: 9)
        for row in 0..<3 { for column in 0..<3 { for k in 0..<3 {
            result[row*3+column] += a[row*3+k] * b[k*3+column]
        } } }
        return result
    }
    private static func matches(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) <= max(1e-8, abs(expected) * 1e-9)
    }
}
