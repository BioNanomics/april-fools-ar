import XCTest
import Foundation

/// Exercises the production recorder without an ARSession or camera buffers.
/// Camera acquisition remains a separate hardware acceptance check.
final class RecordingModeTests: XCTestCase {
    private let mib: Int64 = 1024 * 1024

    private func recorder(_ mode: RecordingMode = .facts) throws -> CaptureRecorder {
        let value = try CaptureRecorder(name: "Summary walk", debugSettings: TagDebugSettings(),
            application: ["version": "fixture", "build": "1", "buildCommit": "fixture", "buildDateUTC": "fixture", "workingTreeDirty": false],
            mode: mode)
        addTeardownBlock { try? FileManager.default.removeItem(at: value.folder) }
        return value
    }

    private func summary(count: Int = 1, entries: Int = 1, recording: Bool = false) -> [String: Any] {
        ["schemaVersion": 1, "summaryVersion": 2,
         "field": ["recording": recording,
             "seenTags": [["id": 7, "family": "tag36h11", "count": count,
                 "observedWorldPosition": [1.0, 2.0, 3.0], "segmentId": "segment-a", "timestamp": 112.0,
                 "observedPosition": NSNull(), "nominalPosition": NSNull()]],
             "notSeenTags": [["id": 8, "family": "tag36h11", "status": "notSeen", "nominalPosition": [4.0, 5.0, 6.0]]],
             "inventoryCapacity": ["usedEntries": entries, "limitEntries": 512, "observationCount": count]],
         "registrationEvents": [], "accuracyValidated": false]
    }

    @discardableResult
    private func finish(_ recorder: CaptureRecorder) throws -> [String: Any] {
        let done = expectation(description: "recorder finalization")
        var result: Result<[String: Any], Error>?
        recorder.finish(droppedFrames: 0) { value in result = value; done.fulfill() }
        wait(for: [done], timeout: 20)
        return try XCTUnwrap(result).get()
    }

    private func manifest(_ recorder: CaptureRecorder) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: recorder.folder.appendingPathComponent("manifest.json"))) as? [String: Any])
    }

    func testFactsFinalizesDurableYAMLWithoutMediaLogsOrMP4Preparation() throws {
        let capture = try recorder()
        capture.event(["type": "bookmark", "note": "This media event must not create a log."])
        capture.updateFacts(summary(), timestamp: 100)
        let result = try finish(capture)
        XCTAssertEqual(result["recordingMode"] as? String, "facts")
        XCTAssertEqual(result["finalized"] as? Bool, true)
        XCTAssertEqual(result["summaryReady"] as? Bool, true)
        XCTAssertNil(result["recordingError"])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: capture.folder.path)),
            Set(["manifest.json", "field-walk-summary.yaml"]))
        let stored = try SavedFieldWalk.load(id: capture.id, sessionsRoot: CaptureRecorder.root)
        XCTAssertEqual(stored.descriptor["format"] as? String, "yaml")
        XCTAssertEqual(stored.descriptor["mimeType"] as? String, "application/yaml")
        XCTAssertEqual(stored.url.pathExtension, "yaml")
        XCTAssertTrue(stored.url.isFileURL)
        XCTAssertEqual(stored.manifest["recordingMode"] as? String, "facts")
        XCTAssertTrue(stored.manifest["videoContent"] is NSNull)
        let facts = try XCTUnwrap(stored.summary["field"] as? [String: Any])
        XCTAssertEqual((facts["seenTags"] as? [[String: Any]])?.first?["id"] as? Int, 7)
        XCTAssertEqual((facts["notSeenTags"] as? [[String: Any]])?.first?["status"] as? String, "notSeen")
        XCTAssertEqual((stored.summary["capture"] as? [String: Any])?["videoRecorded"] as? Bool, false)
        XCTAssertNotEqual(SavedRecordingStore.shared.descriptor(sessionID: capture.id)["recordingReady"] as? Bool, true)
        let movie = CaptureRecorder.root.deletingLastPathComponent().appendingPathComponent("recordings/\(capture.id).mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: movie.path))
    }

    func testRepeatedFactsCheckpointsReplaceSummaryAndPreserveDurationAndCounts() throws {
        let capture = try recorder()
        capture.updateFacts(summary(count: 1, recording: true), timestamp: 100)
        capture.updateFacts(summary(count: 4, recording: true), timestamp: 105)
        capture.updateFacts(summary(count: 9), timestamp: 112)
        let result = try finish(capture)
        XCTAssertEqual(result["durationSeconds"] as? Double, 12)
        let stored = try SavedFieldWalk.load(id: capture.id, sessionsRoot: CaptureRecorder.root)
        let field = try XCTUnwrap(stored.summary["field"] as? [String: Any])
        let rows = try XCTUnwrap(field["seenTags"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["count"] as? Int, 9)
        XCTAssertEqual(field["recording"] as? Bool, false)
        XCTAssertEqual((stored.manifest["aprilTagCounts"] as? [String: Any])?["tagObservations"] as? Int, 9)
        XCTAssertEqual((stored.manifest["counts"] as? [String: Any])?["videoFrames"] as? Int, 0)
        XCTAssertEqual((stored.manifest["fileInventory"] as? [[String: Any]])?.count, 1)
    }

    func testBurstCheckpointsStayBoundedAndCannotSkipTheFinalFactsSnapshot() throws {
        let capture = try recorder()
        let initialProgress = expectation(description: "initial checkpoint reached disk queue")
        let releaseDisk = DispatchSemaphore(value: 0)
        defer { releaseDisk.signal() }
        var progressCount = 0
        capture.onProgress = { _ in
            progressCount += 1
            if progressCount == 1 {
                initialProgress.fulfill()
                XCTAssertEqual(releaseDisk.wait(timeout: .now() + 10), .success)
            }
        }
        capture.updateFacts(summary(count: 1, recording: true), timestamp: 100)
        wait(for: [initialProgress], timeout: 10)
        // Hold the disk queue so exactly one periodic checkpoint can enter;
        // all remaining intermediates must be skipped rather than retained.
        for n in 2...101 {
            capture.checkpointFacts(summary(count: n, recording: true), timestamp: 100 + Double(n))
        }
        capture.updateFacts(summary(count: 777), timestamp: 777)
        releaseDisk.signal()
        let result = try finish(capture)
        capture.onProgress = nil
        XCTAssertEqual(progressCount, 3)
        XCTAssertEqual(result["durationSeconds"] as? Double, 677)
        let stored = try SavedFieldWalk.load(id: capture.id, sessionsRoot: CaptureRecorder.root)
        let field = try XCTUnwrap(stored.summary["field"] as? [String: Any])
        XCTAssertEqual((field["seenTags"] as? [[String: Any]])?.first?["count"] as? Int, 777)
        XCTAssertEqual(field["recording"] as? Bool, false)
        XCTAssertEqual((stored.manifest["aprilTagCounts"] as? [String: Any])?["tagObservations"] as? Int, 777)
    }

    func testFactsWithoutFinalSummaryAndEmptyVideoRemainUnfinalized() throws {
        let facts = try recorder()
        XCTAssertThrowsError(try finish(facts))
        XCTAssertEqual(try manifest(facts)["finalized"] as? Bool, false)
        XCTAssertThrowsError(try SavedFieldWalk.load(id: facts.id, sessionsRoot: CaptureRecorder.root))
        let video = try recorder(.video)
        XCTAssertThrowsError(try finish(video))
        XCTAssertEqual(try manifest(video)["finalized"] as? Bool, false)
    }

    func testExpiredFactsFinalizationRetainsRecoveryCheckpoint() throws {
        let capture = try recorder()
        capture.updateFacts(summary(), timestamp: 100)
        capture.backgroundExecutionExpired()
        XCTAssertThrowsError(try finish(capture))
        XCTAssertEqual(try manifest(capture)["finalized"] as? Bool, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.folder.appendingPathComponent("field-walk-summary.yaml").path))
        XCTAssertThrowsError(try SavedFieldWalk.load(id: capture.id, sessionsRoot: CaptureRecorder.root))
    }

    func testSummaryTamperingIsRejected() throws {
        let capture = try recorder()
        capture.updateFacts(summary(), timestamp: 100)
        try finish(capture)
        let url = capture.folder.appendingPathComponent("field-walk-summary.yaml")
        var bytes = try Data(contentsOf: url)
        bytes.append(Data("# modified\n".utf8))
        try bytes.write(to: url)
        XCTAssertThrowsError(try SavedFieldWalk.load(id: capture.id, sessionsRoot: CaptureRecorder.root))
    }

    func testSummaryManifestAndFolderSymlinksAreRejected() throws {
        for name in ["field-walk-summary.yaml", "manifest.json"] {
            let capture = try recorder()
            capture.updateFacts(summary(), timestamp: 100)
            try finish(capture)
            let original = capture.folder.appendingPathComponent(name)
            let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: original, to: outside)
            addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
            try FileManager.default.removeItem(at: original)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
            XCTAssertThrowsError(try SavedFieldWalk.load(id: capture.id, sessionsRoot: CaptureRecorder.root), name)
        }
        let capture = try recorder()
        capture.updateFacts(summary(), timestamp: 100)
        try finish(capture)
        let linkID = UUID().uuidString
        let link = CaptureRecorder.root.appendingPathComponent(linkID)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: capture.folder)
        addTeardownBlock { try? FileManager.default.removeItem(at: link) }
        XCTAssertThrowsError(try SavedFieldWalk.load(id: linkID, sessionsRoot: CaptureRecorder.root))
    }

    func testFactsInventoryProgressRequestsSaveBeforeEntryCapacity() throws {
        let capture = try recorder()
        let progress = expectation(description: "facts inventory capacity")
        capture.onProgress = { values in
            guard let capacity = values["recordingCapacity"] as? [String: Any], capacity["limitingResource"] as? String == "Discovered tags" else { return }
            XCTAssertEqual(capacity["unit"] as? String, "entries")
            XCTAssertEqual(capacity["shouldStop"] as? Bool, true)
            XCTAssertEqual(capacity["limitBytes"] as? Int64, 512)
            progress.fulfill()
        }
        capture.updateFacts(summary(entries: 487), timestamp: 100)
        wait(for: [progress], timeout: 10)
        capture.onProgress = nil
        try finish(capture)
    }

    func testFactsCapacityReservesExpectedTagsBeforeCountingDiscoveredTags() throws {
        let capture = try recorder()
        var document = summary(entries: 245)
        var field = try XCTUnwrap(document["field"] as? [String: Any])
        field["expectedCount"] = 256
        field["discoveredCount"] = 245
        document["field"] = field
        let progress = expectation(description: "discovered tags approach unreserved capacity")
        capture.onProgress = { values in
            guard let capacity = values["recordingCapacity"] as? [String: Any] else {
                XCTFail("Facts progress must include recording capacity")
                return
            }
            XCTAssertEqual(capacity["limitingResource"] as? String, "Tags outside the field definition")
            XCTAssertEqual(capacity["unit"] as? String, "entries")
            XCTAssertEqual((capacity["usedBytes"] as? NSNumber)?.int64Value, 245)
            XCTAssertEqual((capacity["limitBytes"] as? NSNumber)?.int64Value, 256)
            XCTAssertEqual(capacity["fractionUsed"] as? Double, 245.0 / 256.0)
            XCTAssertEqual(capacity["shouldStop"] as? Bool, true)
            progress.fulfill()
        }
        capture.updateFacts(document, timestamp: 100)
        wait(for: [progress], timeout: 10)
        capture.onProgress = nil
        try finish(capture)
    }

    func testOversizedVideoEventRequestsSaveBeforeAnyMetadataLimitWasReached() throws {
        let capture = try recorder(.video)
        let initialBytes = try Data(contentsOf: capture.folder.appendingPathComponent("events.jsonl")).count
        XCTAssertLessThan(Int64(initialBytes), RecordingCapacity.metadataBytes / 100)
        let progress = expectation(description: "oversized event requests automatic save")
        capture.onProgress = { values in
            guard let capacity = values["recordingCapacity"] as? [String: Any],
                  capacity["limitingResource"] as? String == "Event metadata" else { return }
            XCTAssertEqual(capacity["shouldStop"] as? Bool, true)
            XCTAssertEqual(capacity["fractionUsed"] as? Double, 1)
            XCTAssertEqual((capacity["remainingBytes"] as? NSNumber)?.int64Value, 0)
            XCTAssertEqual((capacity["limitBytes"] as? NSNumber)?.int64Value, RecordingCapacity.metadataBytes)
            XCTAssertEqual(capacity["unit"] as? String, "bytes")
            // Existing data was still tiny. The incoming row itself exhausts
            // capacity, so usage alone must not suppress the stop request.
            progress.fulfill()
        }
        capture.event(["type": "oversized-note", "note": String(repeating: "x", count: Int(RecordingCapacity.metadataBytes))])
        wait(for: [progress], timeout: 20)
        capture.onProgress = nil
        XCTAssertThrowsError(try finish(capture)) { error in
            XCTAssertTrue(error.localizedDescription.contains("No completed camera video"))
        }
        let eventBytes = try Data(contentsOf: capture.folder.appendingPathComponent("events.jsonl"))
        XCTAssertLessThan(Int64(eventBytes.count), RecordingCapacity.metadataBytes)
        XCTAssertLessThan(eventBytes.count, 10_000)
        XCTAssertFalse(String(decoding: eventBytes, as: UTF8.self).contains("oversized-note"))
        XCTAssertEqual(try manifest(capture)["finalized"] as? Bool, false)
    }

    func testMetadataBudgetsAre32MiBPerFileRatherThanCombined() {
        XCTAssertEqual(RecordingCapacity.metadataBytes, 32 * mib)
        let capacity = RecordingCapacity.snapshot(mode: .video, frameBytes: 24 * mib, eventBytes: 24 * mib)
        XCTAssertEqual(capacity["fractionUsed"] as? Double, 0.75)
        XCTAssertEqual(capacity["limitBytes"] as? Int64, 32 * mib)
        XCTAssertEqual(capacity["remainingBytes"] as? Int64, 8 * mib)
        XCTAssertEqual(capacity["shouldStop"] as? Bool, false)
    }

    func testCapacityChoosesMostRestrictiveResourceWithItsUnits() {
        let capacity = RecordingCapacity.snapshot(mode: .video, eventBytes: 24 * mib, frameRecords: 99_000, fileEntries: 60_000)
        XCTAssertEqual(capacity["limitingResource"] as? String, "Frame records")
        XCTAssertEqual(capacity["unit"] as? String, "records")
        XCTAssertEqual(capacity["fractionUsed"] as? Double, 0.99)
        XCTAssertEqual(capacity["shouldStop"] as? Bool, true)
        let files = RecordingCapacity.snapshot(mode: .video, eventBytes: 24 * mib, fileEntries: 60_000)
        XCTAssertEqual(files["limitingResource"] as? String, "Capture files")
        XCTAssertEqual(files["unit"] as? String, "entries")
    }

    func testReadableYAMLCapacityIsCheckedIndependentlyFromSourceJSON() {
        let capacity = RecordingCapacity.snapshot(mode: .video, eventBytes: 8 * mib, eventYAMLBytes: 60 * mib)
        XCTAssertEqual(capacity["limitingResource"] as? String, "Event YAML metadata")
        XCTAssertEqual(capacity["limitBytes"] as? Int64, 64 * mib)
        XCTAssertEqual(capacity["fractionUsed"] as? Double, 60.0 / 64.0)
        XCTAssertEqual(capacity["shouldStop"] as? Bool, false)
        let threshold = RecordingCapacity.snapshot(mode: .video, eventYAMLBytes: Int64(ceil(Double(64 * mib) * 0.95)))
        XCTAssertEqual(threshold["shouldStop"] as? Bool, true)
    }

    func testAutomaticSaveStartsAt95PercentAndPackageEstimateIsLabeled() {
        let limit = RecordingCapacity.metadataBytes
        let below = RecordingCapacity.snapshot(mode: .video, eventBytes: Int64(Double(limit) * 0.949))
        XCTAssertEqual(below["shouldStop"] as? Bool, false)
        let threshold = RecordingCapacity.snapshot(mode: .video, eventBytes: Int64(ceil(Double(limit) * 0.95)))
        XCTAssertEqual(threshold["automaticSaveFraction"] as? Double, 0.95)
        XCTAssertEqual(threshold["shouldStop"] as? Bool, true)
        let package = RecordingCapacity.snapshot(mode: .video, sourceBytes: Int64(Double(RecordingCapacity.packageBytes) * 0.96))
        XCTAssertEqual(package["limitingResource"] as? String, "Packaged recording")
        XCTAssertEqual(package["estimated"] as? Bool, true)
        XCTAssertEqual(package["shouldStop"] as? Bool, true)
    }

    func testSavingReservesRoomForThePackageAnd250MBStorageMargin() {
        let low = RecordingCapacity.snapshot(mode: .video, sourceBytes: 300_000_000, availableStorage: 400_000_000)
        XCTAssertEqual(low["limitingResource"] as? String, "Storage for saving")
        XCTAssertEqual(low["limitBytes"] as? Int64, 150_000_000)
        XCTAssertEqual(low["estimated"] as? Bool, true)
        XCTAssertEqual(low["shouldStop"] as? Bool, true)
        let enough = RecordingCapacity.snapshot(mode: .video, sourceBytes: 300_000_000, availableStorage: 2_000_000_000)
        XCTAssertEqual(enough["shouldStop"] as? Bool, false)
    }

    func testFactsCapacityDoesNotConsumeVideoOrFrameLogBudgets() {
        let facts = RecordingCapacity.snapshot(mode: .facts, frameBytes: 100 * mib, eventBytes: 100 * mib,
            frameRecords: 200_000, eventRecords: 200_000, sourceBytes: 10_000 * mib, fileEntries: 100_000, summaryBytes: mib)
        XCTAssertEqual(facts["limitingResource"] as? String, "Tag facts summary")
        XCTAssertEqual(facts["fractionUsed"] as? Double, 1.0 / 32.0)
        XCTAssertEqual(facts["shouldStop"] as? Bool, false)
    }
}
