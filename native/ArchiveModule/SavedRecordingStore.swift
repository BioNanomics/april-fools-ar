import Foundation
import CryptoKit
import CoreFoundation
import Darwin

/// Durable recordings are published outside their immutable capture folders.
/// A receipt is committed last, so an interrupted save is always retryable.
final class SavedRecordingStore {
    static let shared: SavedRecordingStore = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AprilFoolsAR", isDirectory: true)
        return SavedRecordingStore(sessionsRoot: documents.appendingPathComponent("sessions", isDirectory: true),
                                   recordingsRoot: documents.appendingPathComponent("recordings", isDirectory: true))
    }()

    private struct Identity: Codable, Equatable {
        let bytes: UInt64
        let inode: UInt64
        let device: UInt64
        let modified: Double
    }
    private struct Receipt: Codable {
        let version: Int
        let sessionID: String
        let sourceManifestSHA256: String
        let recordingSHA256: String
        let identity: Identity
    }
    private struct Source {
        let folder: URL
        let id: String
        let manifestSHA256: String
        let manifest: [String: Any]
    }
    private struct Verified {
        let receipt: Receipt
        let identity: Identity
    }

    private let sessionsRoot: URL
    private let recordingsRoot: URL
    private let prepareLock = NSLock()
    private let verificationLock = NSLock()
    private var verified: [String: Verified] = [:]
    private let manager = FileManager.default

    init(sessionsRoot: URL, recordingsRoot: URL) {
        self.sessionsRoot = sessionsRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.recordingsRoot = recordingsRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Reuses a verified artifact. All callers share one publication transaction.
    func prepare(folderPath: String, shouldCancel: () -> Bool = { false }) throws -> SessionMP4Writer.Result {
        prepareLock.lock()
        defer { prepareLock.unlock() }
        try checkCancellation(shouldCancel)
        let source = try source(folderPath: folderPath)
        guard recordingsRoot.path != source.folder.path,
              !recordingsRoot.path.hasPrefix(source.folder.path + "/") else {
            throw failure("The recording destination must be outside its capture folder.")
        }
        try manager.createDirectory(at: recordingsRoot, withIntermediateDirectories: true)
        let lock = try acquirePublicationLock(shouldCancel: shouldCancel)
        defer { _ = flock(lock, LOCK_UN); Darwin.close(lock) }
        // The process lock guarantees no other well-behaved store can own a
        // stage here. Only this writer's exact private naming scheme is removed.
        try removeInterruptedStages()
        let destination = movieURL(source.id)
        if let receipt = receipt(source: source), let identity = try? fileIdentity(destination),
           identity == receipt.identity {
            verificationLock.lock()
            let prior = verified[source.id]
            verificationLock.unlock()
            if prior?.identity == identity,
               prior?.receipt.recordingSHA256 == receipt.recordingSHA256,
               prior?.receipt.sourceManifestSHA256 == source.manifestSHA256 {
                try checkCancellation(shouldCancel)
                return SessionMP4Writer.Result(url: destination, bytes: identity.bytes)
            }
            if try hashFile(destination, shouldCancel: shouldCancel) == receipt.recordingSHA256,
               try fileIdentity(destination) == identity {
                remember(receipt, id: source.id)
                return SessionMP4Writer.Result(url: destination, bytes: identity.bytes)
            }
        }

        let staging = recordingsRoot.appendingPathComponent(".\(source.id)-\(UUID().uuidString).pending", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let transform = VideoOrientation.playbackTransform(manifest: source.manifest,
                                                           firstFrame: try firstFrame(source.folder))
        let output = try SessionMP4Writer().archiveSession(folderPath: source.folder.path,
            allowedSessionsRoot: sessionsRoot, destinationDirectory: staging,
            playbackTransform: transform, shouldCancel: shouldCancel)
        try checkCancellation(shouldCancel)
        guard try self.source(folderPath: source.folder.path).manifestSHA256 == source.manifestSHA256 else {
            throw failure("The capture manifest changed while saving. Try again after recording has stopped.")
        }
        let digest = try hashFile(output.url, shouldCancel: shouldCancel)
        let identity = try fileIdentity(output.url)
        guard identity.bytes == output.bytes, identity.bytes > 0 else { throw failure("The saved recording is incomplete.") }
        let receipt = Receipt(version: 1, sessionID: source.id,
            sourceManifestSHA256: source.manifestSHA256, recordingSHA256: digest, identity: identity)
        let receiptData = try JSONEncoder().encode(receipt)
        try checkCancellation(shouldCancel)
        // rename is atomic and also replaces an obsolete artifact without a gap.
        guard Darwin.rename(output.url.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        // The receipt is the ready marker. Expiration here leaves a complete but
        // unpublished movie; the immutable source can be used by the next retry.
        try checkCancellation(shouldCancel)
        try receiptData.write(to: receiptURL(source.id), options: .atomic)
        remember(receipt, id: source.id)
        return SessionMP4Writer.Result(url: destination, bytes: identity.bytes)
    }

    /// Cheap listing check: only the small manifest/receipt and file attributes
    /// are read. The movie itself is hashed when first prepared in this process.
    func descriptor(sessionID: String) -> [String: Any] {
        guard UUID(uuidString: sessionID) != nil,
              let source = try? source(folderPath: sessionsRoot.appendingPathComponent(sessionID).path),
              let receipt = receipt(source: source),
              let identity = try? fileIdentity(movieURL(source.id)), identity == receipt.identity else {
            return ["recordingReady": false]
        }
        let url = movieURL(source.id)
        return ["recordingReady": true, "recordingURL": url.absoluteString,
                "recordingPath": url.path, "recordingBytes": NSNumber(value: identity.bytes)]
    }

    /// Explicit deletion removes both copies, including a capture whose save
    /// failed. Keep the source until last so an artifact-cleanup failure is
    /// visible in Saved sessions and can be retried.
    func delete(sessionID: String) throws {
        guard let identifier = UUID(uuidString: sessionID) else { throw failure("Invalid session identifier.") }
        prepareLock.lock()
        defer { prepareLock.unlock() }
        try requireDirectory(sessionsRoot)
        let folder = sessionsRoot.appendingPathComponent(sessionID, isDirectory: true)
        guard folder.deletingLastPathComponent().path == sessionsRoot.path else {
            throw failure("Select one session directly inside the sessions folder.")
        }
        if let attributes = try optionalAttributes(folder) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  folder.resolvingSymlinksInPath().deletingLastPathComponent().path == sessionsRoot.path else {
                throw failure("The session must be a local capture directory, not a link.")
            }
        }
        guard recordingsRoot.path != folder.path,
              !recordingsRoot.path.hasPrefix(folder.path + "/"),
              !sessionsRoot.path.hasPrefix(recordingsRoot.path + "/") else {
            throw failure("The recording destination must be outside the capture folders.")
        }
        try manager.createDirectory(at: recordingsRoot, withIntermediateDirectories: true)
        let lock = try acquirePublicationLock(shouldCancel: { false })
        defer { _ = flock(lock, LOCK_UN); Darwin.close(lock) }

        let artifacts = [movieURL(sessionID), receiptURL(sessionID)]
        // Validate every target before removing anything. Never follow a link
        // or recursively remove an unexpected directory in place of a movie.
        for artifact in artifacts {
            if let attributes = try optionalAttributes(artifact),
               attributes[.type] as? FileAttributeType != .typeRegular {
                throw failure("A saved recording file has an unexpected type.")
            }
        }
        let stages = try manager.contentsOfDirectory(at: recordingsRoot, includingPropertiesForKeys: nil)
            .filter { stageSessionID($0) == identifier }
        for stage in stages { try requireDirectory(stage) }
        for artifact in artifacts where try optionalAttributes(artifact) != nil { try manager.removeItem(at: artifact) }
        for stage in stages { try manager.removeItem(at: stage) }
        if try optionalAttributes(folder) != nil { try manager.removeItem(at: folder) }
        verificationLock.lock()
        verified = verified.filter { UUID(uuidString: $0.key) != identifier }
        verificationLock.unlock()
    }

    private func optionalAttributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try manager.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }

    private func requireDirectory(_ url: URL) throws {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw failure("Expected a local recording directory, not a link.")
        }
    }

    private func source(folderPath: String) throws -> Source {
        let decoded = folderPath.removingPercentEncoding ?? folderPath
        guard !decoded.contains("\0"), !decoded.split(separator: "/").contains("..") else {
            throw failure("Invalid session path.")
        }
        let supplied: URL
        if folderPath.hasPrefix("file:") {
            guard let url = URL(string: folderPath), url.isFileURL,
                  url.host == nil || url.host == "" || url.host == "localhost" else { throw failure("Expected a local session folder.") }
            supplied = url
        } else {
            guard folderPath.hasPrefix("/") else { throw failure("Expected an absolute session path.") }
            supplied = URL(fileURLWithPath: folderPath, isDirectory: true)
        }
        let path = supplied.standardizedFileURL
        let attributes = try manager.attributesOfItem(atPath: path.path)
        let canonical = path.resolvingSymlinksInPath()
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              UUID(uuidString: path.lastPathComponent) != nil,
              path.deletingLastPathComponent().resolvingSymlinksInPath().path == sessionsRoot.path,
              canonical.deletingLastPathComponent().path == sessionsRoot.path else { throw failure("Select one session directly inside the sessions folder.") }
        let manifest = canonical.appendingPathComponent("manifest.json")
        let identity = try fileIdentity(manifest)
        guard identity.bytes <= 16 * 1024 * 1024 else { throw failure("The capture manifest is too large.") }
        let data = try Data(contentsOf: manifest)
        guard try fileIdentity(manifest) == identity,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let finalized = value["finalized"] as? NSNumber,
              CFGetTypeID(finalized) == CFBooleanGetTypeID(), finalized.boolValue else {
            throw failure("Stop and finalize this recording before saving it.")
        }
        return Source(folder: canonical, id: path.lastPathComponent, manifestSHA256: hash(data), manifest: value)
    }

    private func firstFrame(_ folder: URL) throws -> [String: Any]? {
        let url = folder.appendingPathComponent("frames.jsonl")
        _ = try fileIdentity(url)
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw failure("Unable to read the first recorded frame.") }
        let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? input.close() }
        var line = Data()
        while let chunk = try input.read(upToCount: 16_384), !chunk.isEmpty {
            for byte in chunk {
                if byte == 10 {
                    if !line.allSatisfy({ [9, 13, 32].contains($0) }) {
                        return try JSONSerialization.jsonObject(with: line) as? [String: Any]
                    }
                    line.removeAll(keepingCapacity: true)
                } else {
                    guard line.count < 1_048_576 else { throw failure("The first recorded frame is too large.") }
                    line.append(byte)
                }
            }
        }
        return line.isEmpty ? nil : try JSONSerialization.jsonObject(with: line) as? [String: Any]
    }

    /// A separate open description per prepare makes flock serialize both
    /// independent store instances and other processes using this directory.
    private func acquirePublicationLock(shouldCancel: () -> Bool) throws -> Int32 {
        let rootAttributes = try manager.attributesOfItem(atPath: recordingsRoot.path)
        guard rootAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw failure("The recording destination must be a local directory.")
        }
        let url = recordingsRoot.appendingPathComponent(".prepare.lock")
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw failure("Unable to lock the recording destination.") }
        var status = stat()
        guard fstat(fd, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == geteuid(), status.st_nlink == 1 else {
            Darwin.close(fd)
            throw failure("The recording lock must be a private regular file.")
        }
        do {
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else {
                    throw failure("Unable to acquire the recording destination lock.")
                }
                try checkCancellation(shouldCancel)
                Thread.sleep(forTimeInterval: 0.02)
            }
            try checkCancellation(shouldCancel)
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private func removeInterruptedStages() throws {
        for entry in try manager.contentsOfDirectory(at: recordingsRoot, includingPropertiesForKeys: nil) {
            guard stageSessionID(entry) != nil else { continue }
            let attributes = try manager.attributesOfItem(atPath: entry.path)
            // attributesOfItem reports a link itself as .typeSymbolicLink;
            // never follow a matching-name link during cleanup.
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { continue }
            try manager.removeItem(at: entry)
        }
    }

    private func stageSessionID(_ url: URL) -> UUID? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".pending") else { return nil }
        let identifiers = name.dropFirst().dropLast(".pending".count)
        guard identifiers.count == 73 else { return nil }
        let boundary = identifiers.index(identifiers.startIndex, offsetBy: 36)
        guard identifiers[boundary] == "-",
              UUID(uuidString: String(identifiers[identifiers.index(after: boundary)...])) != nil else { return nil }
        return UUID(uuidString: String(identifiers[..<boundary]))
    }

    private func receipt(source: Source) -> Receipt? {
        let url = receiptURL(source.id)
        guard let identity = try? fileIdentity(url), identity.bytes <= 64 * 1024,
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Receipt.self, from: data),
              value.version == 1, value.sessionID == source.id,
              value.sourceManifestSHA256 == source.manifestSHA256,
              value.identity.bytes > 0, value.recordingSHA256.count == 64 else { return nil }
        return value
    }

    private func fileIdentity(_ url: URL) throws -> Identity {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { throw failure("Expected a regular recording file.") }
        return Identity(bytes: size.uint64Value, inode: inode.uint64Value,
                        device: device.uint64Value, modified: modified.timeIntervalSince1970)
    }

    private func hashFile(_ url: URL, shouldCancel: () -> Bool) throws -> String {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw failure("Unable to read the saved recording.") }
        let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? input.close() }
        var digest = SHA256()
        // Do not retain every Foundation read buffer while verifying a movie.
        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { return false }
            try checkCancellation(shouldCancel)
            digest.update(data: data)
            return true
        }) {}
        try checkCancellation(shouldCancel)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func remember(_ receipt: Receipt, id: String) {
        verificationLock.lock()
        verified[id] = Verified(receipt: receipt, identity: receipt.identity)
        verificationLock.unlock()
    }
    private func checkCancellation(_ shouldCancel: () -> Bool) throws {
        if shouldCancel() { throw failure("Saving was interrupted. The original recording is retained; try again.") }
    }
    private func movieURL(_ id: String) -> URL { recordingsRoot.appendingPathComponent("\(id).mp4") }
    private func receiptURL(_ id: String) -> URL { recordingsRoot.appendingPathComponent("\(id).json") }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "AprilFoolsAR.SavedRecording", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
