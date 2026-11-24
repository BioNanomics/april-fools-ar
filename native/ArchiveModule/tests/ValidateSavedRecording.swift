import Foundation

/// Foundation-only lifecycle coverage. The Python harness supplies one valid
/// synthetic finalized capture; no simulator, camera or physical device is used.
@main
enum ValidateSavedRecording {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 4, arguments[0] == "--prepare" {
            let store = SavedRecordingStore(sessionsRoot: URL(fileURLWithPath: arguments[1], isDirectory: true),
                                            recordingsRoot: URL(fileURLWithPath: arguments[3], isDirectory: true))
            let result = try store.prepare(folderPath: arguments[2])
            let attributes = try FileManager.default.attributesOfItem(atPath: result.url.path)
            let resultData = try JSONSerialization.data(withJSONObject: ["path": result.url.path,
                "inode": attributes[.systemFileNumber]!,
                "modified": (attributes[.modificationDate] as! Date).timeIntervalSince1970], options: .sortedKeys)
            print(String(decoding: resultData, as: UTF8.self))
            return
        }
        guard arguments.count == 3 else { throw failure("Expected SESSIONS_ROOT SESSION_DIRECTORY RECORDINGS_ROOT") }
        let manager = FileManager.default
        let root = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let source = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let recordings = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let store = SavedRecordingStore(sessionsRoot: root, recordingsRoot: recordings)
        let originals = try contents(source)
        try manager.createDirectory(at: recordings, withIntermediateDirectories: true)
        let staleStage = recordings.appendingPathComponent(".\(source.lastPathComponent)-\(UUID().uuidString).pending", isDirectory: true)
        try manager.createDirectory(at: staleStage, withIntermediateDirectories: false)
        try Data("interrupted movie".utf8).write(to: staleStage.appendingPathComponent("partial.mp4"))
        let unrelated = recordings.appendingPathComponent(".user-notes.pending", isDirectory: true)
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let unrelatedBytes = Data("keep user notes".utf8)
        try unrelatedBytes.write(to: unrelated.appendingPathComponent("notes.txt"))
        let namedFile = recordings.appendingPathComponent(".\(source.lastPathComponent)-\(UUID().uuidString).pending")
        try unrelatedBytes.write(to: namedFile)
        let namedLink = recordings.appendingPathComponent(".\(source.lastPathComponent)-\(UUID().uuidString).pending")
        try manager.createSymbolicLink(at: namedLink, withDestinationURL: unrelated)
        let first = try store.prepare(folderPath: source.path)
        try expect(!manager.fileExists(atPath: staleStage.path), "Interrupted stage was not removed")
        try expect(try Data(contentsOf: unrelated.appendingPathComponent("notes.txt")) == unrelatedBytes, "Cleanup changed unrelated files")
        try expect(try Data(contentsOf: namedFile) == unrelatedBytes, "Cleanup removed a regular file")
        try expect(try manager.attributesOfItem(atPath: namedLink.path)[.type] as? FileAttributeType == .typeSymbolicLink, "Cleanup removed a symlink")
        try expect(first.url.lastPathComponent == source.lastPathComponent + ".mp4", "A saved recording must have a stable name")
        try expect(first.bytes > 0, "The saved movie is empty")
        try expect(store.descriptor(sessionID: source.lastPathComponent)["recordingReady"] as? Bool == true, "Saved movie is not ready")
        let modified = try manager.attributesOfItem(atPath: first.url.path)[.modificationDate] as! Date
        let second = try store.prepare(folderPath: source.absoluteString)
        try expect(first.url == second.url && first.bytes == second.bytes, "Second prepare changed the saved result")
        try expect(try manager.attributesOfItem(atPath: second.url.path)[.modificationDate] as? Date == modified, "Second prepare rewrote the movie")
        let relaunched = SavedRecordingStore(sessionsRoot: root, recordingsRoot: recordings)
        let third = try relaunched.prepare(folderPath: source.path)
        try expect(third.url == first.url, "Relaunch failed to reuse the saved movie")
        try expect(try manager.attributesOfItem(atPath: third.url.path)[.modificationDate] as? Date == modified, "Relaunch repackaged the movie")

        let concurrent = ConcurrentResults()
        let instances = [store, relaunched, SavedRecordingStore(sessionsRoot: root, recordingsRoot: recordings),
                         SavedRecordingStore(sessionsRoot: root, recordingsRoot: recordings)]
        let group = DispatchGroup()
        for instance in instances {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do { concurrent.record(.success(try instance.prepare(folderPath: source.path))) }
                catch { concurrent.record(.failure(error)) }
            }
        }
        group.wait()
        try expect(concurrent.values.count == 4, "Concurrent callers were not completed")
        for result in concurrent.values { try expect(try result.get().url == first.url, "Concurrent prepare returned a different movie") }
        try expect(try contents(source) == originals, "Saving changed the original capture")

        try reject("path traversal") { _ = try store.prepare(folderPath: source.path + "/../" + source.lastPathComponent) }
        try reject("sessions root") { _ = try store.prepare(folderPath: root.path) }
        try reject("relative path") { _ = try store.prepare(folderPath: source.lastPathComponent) }
        try reject("remote URL") { _ = try store.prepare(folderPath: "https://example.com/" + source.lastPathComponent) }
        try expect(store.descriptor(sessionID: "../" + source.lastPathComponent)["recordingReady"] as? Bool == false, "Unsafe descriptor was accepted")
        let linked = root.appendingPathComponent(UUID().uuidString)
        try manager.createSymbolicLink(at: linked, withDestinationURL: source)
        defer { try? manager.removeItem(at: linked) }
        try reject("linked source") { _ = try store.prepare(folderPath: linked.path) }
        let unsafeRoot = recordings.deletingLastPathComponent().appendingPathComponent("unsafe-recordings", isDirectory: true)
        try manager.createDirectory(at: unsafeRoot, withIntermediateDirectories: false)
        try manager.createSymbolicLink(at: unsafeRoot.appendingPathComponent(".prepare.lock"), withDestinationURL: namedFile)
        let unsafeStore = SavedRecordingStore(sessionsRoot: root, recordingsRoot: unsafeRoot)
        try reject("linked lock") { _ = try unsafeStore.prepare(folderPath: source.path) }
        try expect(try Data(contentsOf: namedFile) == unrelatedBytes, "Lock acquisition changed the symlink target")

        func clone() throws -> URL {
            let copy = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.copyItem(at: source, to: copy)
            return copy
        }
        func expectUnpublished(_ directory: URL) throws {
            try expect(store.descriptor(sessionID: directory.lastPathComponent)["recordingReady"] as? Bool == false, "Failed save was exposed as ready")
            let entries = try manager.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)
            try expect(!entries.contains { $0.lastPathComponent.hasPrefix("." + directory.lastPathComponent) }, "Failed save left staging files")
        }

        let broken = try clone()
        let events = broken.appendingPathComponent("events.jsonl")
        let eventBytes = try Data(contentsOf: events)
        try Data("{\"changed\":true}\n".utf8).write(to: events)
        let brokenOriginals = try contents(broken)
        try reject("source digest mismatch") { _ = try store.prepare(folderPath: broken.path) }
        try expect(try contents(broken) == brokenOriginals, "Failed save changed the original capture")
        try expectUnpublished(broken)
        try eventBytes.write(to: events)
        _ = try store.prepare(folderPath: broken.path)
        try expect(store.descriptor(sessionID: broken.lastPathComponent)["recordingReady"] as? Bool == true, "Failed save could not be retried")

        let unfinished = try clone()
        try changeManifest(unfinished) { $0["finalized"] = false }
        try reject("unfinished source") { _ = try store.prepare(folderPath: unfinished.path) }
        try expectUnpublished(unfinished)
        let canceled = try clone()
        let canceledOriginals = try contents(canceled)
        var cancellationChecks = 0
        try reject("canceled package") {
            _ = try store.prepare(folderPath: canceled.path) { cancellationChecks += 1; return cancellationChecks >= 2 }
        }
        try expectUnpublished(canceled)
        try expect(try contents(canceled) == canceledOriginals, "Canceled save changed source files")
        _ = try store.prepare(folderPath: canceled.path)

        let lateCanceled = try clone()
        let lateMovie = recordings.appendingPathComponent(lateCanceled.lastPathComponent + ".mp4")
        try reject("canceled publication") {
            _ = try store.prepare(folderPath: lateCanceled.path) { manager.fileExists(atPath: lateMovie.path) }
        }
        try expectUnpublished(lateCanceled)
        _ = try store.prepare(folderPath: lateCanceled.path)

        let receiptFailure = try clone()
        let receiptDirectory = recordings.appendingPathComponent(receiptFailure.lastPathComponent + ".json", isDirectory: true)
        try manager.createDirectory(at: receiptDirectory, withIntermediateDirectories: false)
        try reject("receipt commit failure") { _ = try store.prepare(folderPath: receiptFailure.path) }
        try expectUnpublished(receiptFailure)
        try manager.removeItem(at: receiptDirectory)
        _ = try store.prepare(folderPath: receiptFailure.path)

        let receipt = recordings.appendingPathComponent(source.lastPathComponent + ".json")
        try manager.removeItem(at: receipt)
        try expect(store.descriptor(sessionID: source.lastPathComponent)["recordingReady"] as? Bool == false, "Missing receipt was accepted")
        _ = try store.prepare(folderPath: source.path)
        try changeManifest(source) { $0["name"] = "Changed finalized manifest" }
        try expect(store.descriptor(sessionID: source.lastPathComponent)["recordingReady"] as? Bool == false, "Changed source manifest reused a stale movie")
        _ = try store.prepare(folderPath: source.path)
        try expect(store.descriptor(sessionID: source.lastPathComponent)["recordingReady"] as? Bool == true, "Changed manifest could not be prepared")
        var bytes = try Data(contentsOf: first.url)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: first.url)
        try expect(store.descriptor(sessionID: source.lastPathComponent)["recordingReady"] as? Bool == false, "Changed movie was accepted")
        _ = try store.prepare(folderPath: source.path)
        try expect(store.descriptor(sessionID: source.lastPathComponent)["recordingReady"] as? Bool == true, "Changed movie could not be recovered")

        let deleted = try clone()
        let deletedMovie = try store.prepare(folderPath: deleted.path).url
        let deletedReceipt = recordings.appendingPathComponent(deleted.lastPathComponent + ".json")
        let deletedStage = recordings.appendingPathComponent(".\(deleted.lastPathComponent)-\(UUID().uuidString).pending", isDirectory: true)
        try manager.createDirectory(at: deletedStage, withIntermediateDirectories: false)
        try Data("partial".utf8).write(to: deletedStage.appendingPathComponent("partial.mp4"))
        let retainedStage = recordings.appendingPathComponent(".\(source.lastPathComponent)-\(UUID().uuidString).pending", isDirectory: true)
        try manager.createDirectory(at: retainedStage, withIntermediateDirectories: false)
        try manager.createSymbolicLink(at: deleted.appendingPathComponent("linked-notes"), withDestinationURL: unrelated)
        try store.delete(sessionID: deleted.lastPathComponent)
        for url in [deleted, deletedMovie, deletedReceipt, deletedStage] {
            try expect(!manager.fileExists(atPath: url.path), "Delete retained a session artifact: " + url.path)
        }
        try expect(manager.fileExists(atPath: retainedStage.path), "Delete removed a different session's staging directory")
        try expect(try Data(contentsOf: unrelated.appendingPathComponent("notes.txt")) == unrelatedBytes, "Delete followed a nested source link")
        try expect(store.descriptor(sessionID: deleted.lastPathComponent)["recordingReady"] as? Bool == false, "Deleted recording retained a ready descriptor")
        try store.delete(sessionID: deleted.lastPathComponent)
        try reject("prepare after deletion") { _ = try store.prepare(folderPath: deleted.path) }
        try expect(try contents(source) != [:] && manager.fileExists(atPath: first.url.path), "Delete changed another saved session")

        // Failed captures need no finalized/valid manifest to be discarded.
        try store.delete(sessionID: unfinished.lastPathComponent)
        try expect(!manager.fileExists(atPath: unfinished.path), "Unfinished source could not be deleted")
        let corrupt = try clone()
        try Data("not JSON".utf8).write(to: corrupt.appendingPathComponent("manifest.json"))
        try store.delete(sessionID: corrupt.lastPathComponent)
        try expect(!manager.fileExists(atPath: corrupt.path), "Corrupt source could not be deleted")
        let orphanID = UUID().uuidString
        let orphanMovie = recordings.appendingPathComponent(orphanID + ".mp4")
        try Data("orphaned movie".utf8).write(to: orphanMovie)
        try store.delete(sessionID: orphanID)
        try expect(!manager.fileExists(atPath: orphanMovie.path), "Deletion retry retained an orphaned movie")

        try reject("delete traversal") { try store.delete(sessionID: "../" + source.lastPathComponent) }
        try reject("delete absolute path") { try store.delete(sessionID: source.path) }
        try reject("delete linked source") { try store.delete(sessionID: linked.lastPathComponent) }
        let unsafeDelete = try clone()
        let unsafeMovie = recordings.appendingPathComponent(unsafeDelete.lastPathComponent + ".mp4")
        try manager.createSymbolicLink(at: unsafeMovie, withDestinationURL: namedFile)
        try reject("delete linked movie") { try store.delete(sessionID: unsafeDelete.lastPathComponent) }
        try expect(manager.fileExists(atPath: unsafeDelete.path), "Unsafe delete removed the source before validating its artifacts")
        try expect(try Data(contentsOf: namedFile) == unrelatedBytes, "Delete followed a movie link")
        try manager.removeItem(at: unsafeMovie)
        let unsafeStage = recordings.appendingPathComponent(".\(unsafeDelete.lastPathComponent)-\(UUID().uuidString).pending")
        try manager.createSymbolicLink(at: unsafeStage, withDestinationURL: unrelated)
        try reject("delete linked stage") { try store.delete(sessionID: unsafeDelete.lastPathComponent) }
        try expect(manager.fileExists(atPath: unsafeDelete.path), "Unsafe stage cleanup removed the source")
        try manager.removeItem(at: unsafeStage)
        try store.delete(sessionID: unsafeDelete.lastPathComponent)
        let replacedRoot = recordings.deletingLastPathComponent().appendingPathComponent("delete-root", isDirectory: true)
        try manager.createDirectory(at: replacedRoot, withIntermediateDirectories: false)
        let replacedStore = SavedRecordingStore(sessionsRoot: root, recordingsRoot: replacedRoot)
        try manager.removeItem(at: replacedRoot)
        try manager.createSymbolicLink(at: replacedRoot, withDestinationURL: recordings)
        try reject("delete linked recording root") { try replacedStore.delete(sessionID: source.lastPathComponent) }
        try expect(manager.fileExists(atPath: source.path) && manager.fileExists(atPath: first.url.path), "Linked-root deletion changed a saved session")
        try manager.removeItem(at: replacedRoot)

        // A second store has its own NSLock; the publication file lock must
        // still hold deletion until an in-flight save has finished.
        let racing = try clone()
        let publisherEntered = DispatchSemaphore(value: 0)
        let resumePublisher = DispatchSemaphore(value: 0)
        defer { resumePublisher.signal() }
        let deletionStarted = DispatchSemaphore(value: 0)
        let deletionCompleted = DispatchSemaphore(value: 0)
        let operations = ConcurrentOperations()
        let racingGroup = DispatchGroup()
        racingGroup.enter()
        DispatchQueue.global().async {
            defer { racingGroup.leave() }
            do {
                var checks = 0
                _ = try store.prepare(folderPath: racing.path) {
                    checks += 1
                    if checks == 2 {
                        publisherEntered.signal()
                        return resumePublisher.wait(timeout: .now() + 10) != .success
                    }
                    return false
                }
                operations.record(.success(()))
            } catch { operations.record(.failure(error)) }
        }
        try expect(publisherEntered.wait(timeout: .now() + 10) == .success, "Concurrent publisher did not acquire its lock")
        racingGroup.enter()
        DispatchQueue.global().async {
            defer { racingGroup.leave(); deletionCompleted.signal() }
            deletionStarted.signal()
            do { try relaunched.delete(sessionID: racing.lastPathComponent); operations.record(.success(())) }
            catch { operations.record(.failure(error)) }
        }
        try expect(deletionStarted.wait(timeout: .now() + 5) == .success, "Concurrent deletion did not start")
        try expect(deletionCompleted.wait(timeout: .now() + 0.15) == .timedOut, "Deletion did not wait for publication")
        resumePublisher.signal()
        try expect(racingGroup.wait(timeout: .now() + 20) == .success, "Concurrent save/delete did not complete")
        try expect(operations.values.count == 2, "Concurrent save/delete omitted a result")
        for result in operations.values { try result.get() }
        try expect(!manager.fileExists(atPath: racing.path), "Concurrent publisher restored the deleted source")
        try expect(!manager.fileExists(atPath: recordings.appendingPathComponent(racing.lastPathComponent + ".mp4").path), "Concurrent publisher restored the deleted movie")
        try expect(!manager.fileExists(atPath: recordings.appendingPathComponent(racing.lastPathComponent + ".json").path), "Concurrent publisher restored the deleted receipt")
        print("SavedRecordingStore: reuse, relaunch, concurrency, recovery, cancellation, containment, source integrity and deletion passed")
    }

    private static func contents(_ directory: URL) throws -> [String: Data] {
        let manager = FileManager.default
        let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(url.path.dropFirst(directory.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }
    private static func changeManifest(_ directory: URL, change: (inout [String: Any]) -> Void) throws {
        let url = directory.appendingPathComponent("manifest.json")
        var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        change(&value)
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url, options: .atomic)
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw failure(message) }
    }
    private static func reject(_ label: String, operation: () throws -> Void) throws {
        do { try operation() }
        catch { return }
        throw failure("Expected rejection: " + label)
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "SavedRecordingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}

private final class ConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<SessionMP4Writer.Result, Error>] = []
    var values: [Result<SessionMP4Writer.Result, Error>] { lock.lock(); defer { lock.unlock() }; return results }
    func record(_ result: Result<SessionMP4Writer.Result, Error>) { lock.lock(); results.append(result); lock.unlock() }
}

private final class ConcurrentOperations: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Void, Error>] = []
    var values: [Result<Void, Error>] { lock.lock(); defer { lock.unlock() }; return results }
    func record(_ result: Result<Void, Error>) { lock.lock(); results.append(result); lock.unlock() }
}
