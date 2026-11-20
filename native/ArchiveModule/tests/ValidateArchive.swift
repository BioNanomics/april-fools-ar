import Foundation

/// Standalone executable: compile with SessionZIPWriter.swift, without React/iOS.
@main
enum ValidateArchive {
    static func main() throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("AprilFoolsAR-ZIP-test-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: work) }
        let root = work.appendingPathComponent("sessions")
        let session = root.appendingPathComponent(UUID().uuidString)
        let output = work.appendingPathComponent("exports")
        try fileManager.createDirectory(at: session, withIntermediateDirectories: true)
        let fixtures: [String: Data] = [
            "manifest.json": Data("{\"finalized\":true,\"name\":\"ZIP fixture\"}\n".utf8),
            ".hidden": Data("hidden files must be included".utf8),
            "nested/été/タグ.json": Data("{\"unicode\":\"✓\"}".utf8),
            "frames/00001.bin": Data((0..<(64 * 1024 * 5 + 19)).map { UInt8(truncatingIfNeeded: $0) }),
            "zero-length.bin": Data()
        ]
        for (name, data) in fixtures {
            let url = session.appendingPathComponent(name)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try fileManager.createDirectory(at: session.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let outside = work.appendingPathComponent("outside.txt")
        try Data("must never be exported".utf8).write(to: outside)
        try fileManager.createSymbolicLink(at: session.appendingPathComponent("excluded-link.txt"), withDestinationURL: outside)
        try fileManager.createSymbolicLink(at: session.appendingPathComponent("excluded-directory"), withDestinationURL: work)

        let writer = SessionZIPWriter()
        let result = try writer.archiveSession(folderPath: session.path, allowedSessionsRoot: root,
                                               destinationDirectory: output)
        try runUnzip(["-t", result.url.path])
        let extracted = work.appendingPathComponent("extracted")
        try runUnzip(["-qq", result.url.path, "-d", extracted.path])
        for (name, expected) in fixtures {
            let extractedData = try Data(contentsOf: extracted.appendingPathComponent(name))
            let originalData = try Data(contentsOf: session.appendingPathComponent(name))
            precondition(extractedData == expected,
                         "Extracted bytes differ for \(name)")
            precondition(originalData == expected,
                         "Original was changed: \(name)")
        }
        precondition(fileManager.fileExists(atPath: extracted.appendingPathComponent("empty").path))
        precondition(!fileManager.fileExists(atPath: extracted.appendingPathComponent("excluded-link.txt").path))
        precondition(!fileManager.fileExists(atPath: extracted.appendingPathComponent("excluded-directory").path))
        let actualBytes = (try fileManager.attributesOfItem(atPath: result.url.path)[.size] as! NSNumber).uint64Value
        precondition(actualBytes == result.bytes)
        let second = try writer.archiveSession(folderPath: session.absoluteString, allowedSessionsRoot: root,
                                               destinationDirectory: output)
        precondition(second.url != result.url, "Every export should get a unique path")
        try runUnzip(["-t", second.url.path])

        try expectRejection("parent traversal") {
            _ = try writer.archiveSession(folderPath: session.path + "/../" + session.lastPathComponent,
                                         allowedSessionsRoot: root, destinationDirectory: output)
        }
        try expectRejection("sessions root itself") {
            _ = try writer.archiveSession(folderPath: root.path, allowedSessionsRoot: root, destinationDirectory: output)
        }
        let outsideSession = work.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: outsideSession, withIntermediateDirectories: true)
        try expectRejection("outside sessions root") {
            _ = try writer.archiveSession(folderPath: outsideSession.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let symlinkSession = root.appendingPathComponent(UUID().uuidString)
        try fileManager.createSymbolicLink(at: symlinkSession, withDestinationURL: session)
        try expectRejection("symbolic-link session") {
            _ = try writer.archiveSession(folderPath: symlinkSession.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let oversized = root.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: oversized, withIntermediateDirectories: true)
        let sparse = oversized.appendingPathComponent("too-large.bin")
        precondition(fileManager.createFile(atPath: sparse.path, contents: nil))
        let sparseHandle = try FileHandle(forWritingTo: sparse)
        try sparseHandle.truncate(atOffset: UInt64(UInt32.max))
        try sparseHandle.close()
        try expectRejection("ZIP64 sparse input") {
            _ = try writer.archiveSession(folderPath: oversized.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        print("PASS: unzip integrity, exact binary/Unicode/hidden/empty-file contents, empty directories, original preservation, unique file-URL export, symlink exclusion, path containment/traversal and ZIP64 rejection.")
    }

    private static func expectRejection(_ reason: String, _ action: () throws -> Void) throws {
        do {
            try action()
            fatalError("Expected rejection: \(reason)")
        } catch {
            print("Rejected \(reason): \(error.localizedDescription)")
        }
    }

    private static func runUnzip(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ValidateArchive", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "unzip failed"])
        }
    }
}
