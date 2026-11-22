import Foundation
import CoreFoundation

/// Build identity comes from bundled resources, never the source checkout at runtime.
enum AppBuildInfo {
    static let application = application(in: .main)

    static var info: [String: Any] { info(application: application, in: .main) }

    /// Bundle injection allows verification against real fixture resources.
    static func application(in bundle: Bundle) -> [String: Any] {
        if let url = bundle.url(forResource: "BuildInfo", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let normalized = canonicalApplication(raw) { return normalized }
        let plist = bundle.infoDictionary ?? [:]
        return [
            "bundleId": bundle.bundleIdentifier ?? "unknown",
            "version": text(plist["CFBundleShortVersionString"]),
            "build": text(plist["CFBundleVersion"]),
            "buildCommit": text(plist["BuildCommit"]),
            "buildDateUTC": text(plist["BuildDateUTC"]),
            "workingTreeDirty": plistBoolean(plist["BuildWorkingTreeDirty"]),
        ]
    }

    static func info(in bundle: Bundle) -> [String: Any] {
        info(application: application(in: bundle), in: bundle)
    }

    private static func info(application: [String: Any], in bundle: Bundle) -> [String: Any] {
        var result = application
        do {
            guard let url = bundle.url(forResource: "release-notes", withExtension: "json") else {
                throw BuildInfoError.invalid("Bundled release notes are unavailable.")
            }
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let object = raw as? [String: Any], let releases = object["releases"] as? [[String: Any]] else {
                throw BuildInfoError.invalid("Bundled release notes must contain a releases array.")
            }
            result["releaseNotes"] = try releases.map { release -> [String: Any] in
                guard let version = release["version"] as? String, !version.isEmpty,
                      let build = release["build"] as? String, !build.isEmpty,
                      let title = release["title"] as? String, !title.isEmpty,
                      let changes = release["changes"] as? [String], changes.allSatisfy({ !$0.isEmpty }) else {
                    throw BuildInfoError.invalid("Bundled release entries require version, build, title, and string changes.")
                }
                return ["version": version, "build": build, "title": title, "changes": changes]
            }
        } catch {
            result["releaseNotes"] = [[String: Any]]()
            result["releaseNotesError"] = error.localizedDescription
        }
        return result
    }

    private static func canonicalApplication(_ raw: [String: Any]) -> [String: Any]? {
        var result = [String: Any]()
        for key in ["bundleId", "version", "build", "buildCommit", "buildDateUTC"] {
            guard let value = raw[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            result[key] = value
        }
        guard let dirty = boolean(raw["workingTreeDirty"]) else { return nil }
        result["workingTreeDirty"] = dirty
        return result
    }
    private static func text(_ value: Any?) -> String {
        guard let value = value as? String, !value.isEmpty else { return "unknown" }
        return value
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    private static func plistBoolean(_ value: Any?) -> Bool {
        if let boolean = boolean(value) { return boolean }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }
    private enum BuildInfoError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }
}

/// Version the numerical contract independently from the MP4 and capture schemas.
enum SpatialCoreInfo {
    static var dictionary: [String: Any] { dictionary(application: AppBuildInfo.application) }
    static func dictionary(application: [String: Any]) -> [String: Any] {
        ["name": "april-fools-spatial-core", "version": String(cString: afsc_version()),
         "abiVersion": afsc_abi_version(), "algorithmContractVersion": 1,
         "lengthUnit": "meter", "angleUnit": "radian", "matrixOrder": "column-major",
         "cameraFrame": "optical-x-right-y-down-z-forward", "worldUp": "+Y",
         "buildCommit": application["buildCommit"] as Any? ?? NSNull(),
         "buildDateUTC": application["buildDateUTC"] as Any? ?? NSNull(),
         "workingTreeDirty": application["workingTreeDirty"] as Any? ?? NSNull()]
    }
}
