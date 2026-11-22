import XCTest
import Foundation

final class AppBuildInfoTests: XCTestCase {
    private var fixtures = [URL]()
    private let buildDate = "2026-11-21T12:34:56.789Z"
    private let commit = "0123456789abcdef0123456789abcdef01234567"

    override func tearDown() {
        fixtures.forEach { try? FileManager.default.removeItem(at: $0) }
        fixtures.removeAll()
        super.tearDown()
    }
    private var application: [String: Any] {
        ["bundleId": "org.aprilfools.fixture", "version": "0.2.0", "build": "7", "buildCommit": commit,
         "buildDateUTC": buildDate, "workingTreeDirty": true]
    }
    private func fixture(metadata: [String: Any]? = nil, plistChanges: [String: Any] = [:], notes: Any? = nil) throws -> Bundle {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppBuildInfo-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        fixtures.append(url)
        var plist: [String: Any] = ["CFBundleIdentifier": "org.aprilfools.fallback", "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "2", "CFBundleShortVersionString": "0.1.0", "BuildCommit": "fallback-full-commit",
            "BuildDateUTC": "2020-01-02T03:04:05Z", "BuildWorkingTreeDirty": false]
        plistChanges.forEach { plist[$0.key] = $0.value }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url.appendingPathComponent("Info.plist"))
        if let metadata { try JSONSerialization.data(withJSONObject: metadata).write(to: url.appendingPathComponent("BuildInfo.json")) }
        if let notes { try JSONSerialization.data(withJSONObject: notes).write(to: url.appendingPathComponent("release-notes.json")) }
        return try XCTUnwrap(Bundle(url: url))
    }
    func testBundledBuildInfoIsAuthoritativeAndPreservesExactDateAndCommit() throws {
        let bundle = try fixture(metadata: application)
        let actual = AppBuildInfo.application(in: bundle)
        XCTAssertTrue(NSDictionary(dictionary: actual).isEqual(to: application))
        XCTAssertEqual(actual["buildCommit"] as? String, commit)
        XCTAssertEqual(actual["buildDateUTC"] as? String, buildDate)
        XCTAssertEqual(actual.count, 6)
    }
    func testLegacyPlistFallbackSupportsBooleanAndStringDirtyFlags() throws {
        let flags: [Any] = [true, " true ", "false", false]
        for dirty in flags {
            let bundle = try fixture(plistChanges: ["BuildWorkingTreeDirty": dirty])
            let value = AppBuildInfo.application(in: bundle)
            XCTAssertEqual(value["bundleId"] as? String, "org.aprilfools.fallback")
            XCTAssertEqual(value["version"] as? String, "0.1.0")
            XCTAssertEqual(value["buildCommit"] as? String, "fallback-full-commit")
            XCTAssertEqual(value["buildDateUTC"] as? String, "2020-01-02T03:04:05Z")
            XCTAssertEqual(value["workingTreeDirty"] as? Bool, dirty as? Bool ?? ((dirty as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"))
        }
    }
    func testInvalidStructuredMetadataFallsBackWithoutTreatingNumberAsBoolean() throws {
        var invalid = application; invalid["workingTreeDirty"] = 1
        let bundle = try fixture(metadata: invalid)
        XCTAssertEqual(AppBuildInfo.application(in: bundle)["bundleId"] as? String, "org.aprilfools.fallback")
    }
    func testBundledReleaseNotesAreAvailableAlongsideCanonicalIdentity() throws {
        let releases: [[String: Any]] = [["version": "0.2.0", "build": "7", "title": "Capture identity", "changes": ["Stamp session build metadata."]]]
        let bundle = try fixture(metadata: application, notes: ["releases": releases])
        let info = AppBuildInfo.info(in: bundle)
        XCTAssertEqual(info["buildDateUTC"] as? String, buildDate)
        XCTAssertTrue(NSArray(array: try XCTUnwrap(info["releaseNotes"] as? [[String: Any]])).isEqual(to: releases))
        XCTAssertNil(info["releaseNotesError"])
    }
    func testMissingAndMalformedNotesKeepBuildInfoAvailableAndReportProblem() throws {
        let cases: [Any?] = [nil, ["releases": [["version": "0.2.0", "build": "7", "title": "Missing changes"]]]]
        for notes in cases {
            let bundle = try fixture(metadata: application, notes: notes)
            let info = AppBuildInfo.info(in: bundle)
            XCTAssertEqual(info["releaseNotes"] as? [[String: String]], [])
            XCTAssertNotNil(info["releaseNotesError"] as? String)
            XCTAssertEqual(info["buildCommit"] as? String, commit)
        }
    }
    @MainActor
    func testEmptyRecorderRetainsBuildSnapshotAndDoesNotClaimFinalizedVideo() throws {
        let bundle = try fixture(metadata: application)
        var supplied = AppBuildInfo.application(in: bundle)
        let expected = supplied
        let recorder = try CaptureRecorder(name: "Build metadata fixture", debugSettings: TagDebugSettings(), application: supplied)
        defer { try? FileManager.default.removeItem(at: recorder.folder) }
        supplied["build"] = "changed-after-recording-start"
        let initial = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: recorder.folder.appendingPathComponent("manifest.json"))) as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(initial["application"] as? [String: Any])).isEqual(to: expected))
        XCTAssertEqual(initial["finalized"] as? Bool, false)
        let finished = expectation(description: "recorder finalized without live AR frames")
        recorder.finish(droppedFrames: 0) { result in
            if case .success = result { XCTFail("An empty capture must not claim a playable recording") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: recorder.folder.appendingPathComponent("manifest.json"))) as? [String: Any])
        let saved = try XCTUnwrap(manifest["application"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: saved).isEqual(to: expected))
        XCTAssertEqual(manifest["finalized"] as? Bool, false)
        let core = try XCTUnwrap(manifest["calculationCore"] as? [String: Any])
        XCTAssertEqual(core["version"] as? String, "0.1.0")
        XCTAssertEqual(core["abiVersion"] as? UInt32, 1)
        XCTAssertEqual(core["buildCommit"] as? String, commit)
        XCTAssertEqual(core["buildDateUTC"] as? String, buildDate)
        XCTAssertEqual(core["matrixOrder"] as? String, "column-major")
        XCTAssertNotEqual(manifest["createdAt"] as? String, buildDate)
        let lines = try String(contentsOf: recorder.folder.appendingPathComponent("events.jsonl"), encoding: .utf8).split(separator: "\n")
        let first = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(first["type"] as? String, "recordingStarted")
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(first["application"] as? [String: Any])).isEqual(to: expected))
        XCTAssertNotEqual(first["wallTime"] as? String, buildDate)
    }
}
