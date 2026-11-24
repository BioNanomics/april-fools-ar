import Foundation
import CryptoKit

/// Host-only executable; compile with SessionMP4Writer.swift, without React/iOS.
/// Usage: ValidateMP4 export|check SESSIONS_ROOT SESSION_DIRECTORY OUTPUT_DIRECTORY [AFFINE_JSON]
@main
enum ValidateMP4 {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard (4...5).contains(arguments.count), ["export", "check"].contains(arguments[0]) else {
            throw failure("Usage: ValidateMP4 export|check SESSIONS_ROOT SESSION_DIRECTORY OUTPUT_DIRECTORY [AFFINE_JSON]")
        }
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let session = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let playbackTransform = arguments.count == 5
            ? try JSONSerialization.jsonObject(with: Data(arguments[4].utf8)) as? [Double] : nil
        let writer = SessionMP4Writer()
        let result = try writer.archiveSession(folderPath: session.path, allowedSessionsRoot: root,
                                               destinationDirectory: output, playbackTransform: playbackTransform)
        guard result.url.pathExtension == "mp4" else { throw failure("Export did not use .mp4") }
        let actualBytes = (try fileManager.attributesOfItem(atPath: result.url.path)[.size] as! NSNumber).uint64Value
        guard actualBytes == result.bytes else { throw failure("Result byte count does not match output file") }
        if arguments[0] == "export" {
            let encoded = try JSONSerialization.data(withJSONObject: ["path": result.url.path, "bytes": result.bytes], options: [.sortedKeys])
            print(String(decoding: encoded, as: UTF8.self))
            return
        }

        let second = try writer.archiveSession(folderPath: session.absoluteString, allowedSessionsRoot: root,
                                               destinationDirectory: output)
        guard result.url != second.url else { throw failure("Export filenames must be unique") }
        let completedExports = Set(try fileManager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil).map(\.lastPathComponent))
        for transform in [[0.0, 1, -1, 0, 48], [0, 1, -1, 0, .infinity, 0], [0, 1, -1, 0, 32768, 0]] {
            try expectRejection("invalid playback transform") {
                _ = try writer.archiveSession(folderPath: session.path, allowedSessionsRoot: root,
                                             destinationDirectory: output, playbackTransform: transform)
            }
        }
        try expectRejection("cancelled before export") {
            _ = try writer.archiveSession(folderPath: session.path, allowedSessionsRoot: root,
                                         destinationDirectory: output, shouldCancel: { true })
        }
        var cancelledDuringWrite = false
        try expectRejection("cancelled while streaming output") {
            _ = try writer.archiveSession(folderPath: session.path, allowedSessionsRoot: root,
                                         destinationDirectory: output, shouldCancel: {
                let files = (try? fileManager.contentsOfDirectory(at: output, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                cancelledDuringWrite = files.contains {
                    $0.pathExtension == "partial" && ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 65536
                }
                return cancelledDuringWrite
            })
        }
        guard cancelledDuringWrite else { throw failure("Cancellation fixture did not reach streaming output") }
        try expectRejection("path traversal") {
            _ = try writer.archiveSession(folderPath: session.path + "/../" + session.lastPathComponent,
                                         allowedSessionsRoot: root, destinationDirectory: output)
        }
        try expectRejection("sessions root itself") {
            _ = try writer.archiveSession(folderPath: root.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let work = root.deletingLastPathComponent().appendingPathComponent("native-validation-\(UUID().uuidString)")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        let outside = work.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try expectRejection("source outside sessions root") {
            _ = try writer.archiveSession(folderPath: outside.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let sessionLink = root.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: sessionLink) }
        try fileManager.createSymbolicLink(at: sessionLink, withDestinationURL: session)
        try expectRejection("symlink session") {
            _ = try writer.archiveSession(folderPath: sessionLink.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }

        func changedSession(_ change: (URL) throws -> Void) throws -> URL {
            let changed = root.appendingPathComponent(UUID().uuidString)
            try fileManager.copyItem(at: session, to: changed)
            try change(changed)
            return changed
        }
        let unfinalized = try changedSession { directory in
            let manifestURL = directory.appendingPathComponent("manifest.json")
            var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
            manifest["finalized"] = false
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        }
        defer { try? fileManager.removeItem(at: unfinalized) }
        try expectRejection("unfinalized source") {
            _ = try writer.archiveSession(folderPath: unfinalized.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let corrupt = try changedSession { directory in
            let location = directory.appendingPathComponent("events.jsonl")
            var data = try Data(contentsOf: location)
            guard data.last == 10 else { throw failure("Fixture events must end in a newline") }
            data[data.count - 1] = 32 // Valid JSONL whitespace, same byte count, wrong digest.
            try data.write(to: location)
        }
        defer { try? fileManager.removeItem(at: corrupt) }
        try expectRejection("source inventory mismatch") {
            _ = try writer.archiveSession(folderPath: corrupt.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let linked = try changedSession { directory in
            try fileManager.createSymbolicLink(at: directory.appendingPathComponent("outside-link"), withDestinationURL: outside)
        }
        defer { try? fileManager.removeItem(at: linked) }
        try expectRejection("nested symlink") {
            _ = try writer.archiveSession(folderPath: linked.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let unsupportedName = try changedSession { directory in
            try Data("ambiguous path".utf8).write(to: directory.appendingPathComponent("bad:name.bin"))
        }
        defer { try? fileManager.removeItem(at: unsupportedName) }
        try expectRejection("ambiguous portable filename") {
            _ = try writer.archiveSession(folderPath: unsupportedName.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let truncated = try changedSession { directory in
            let bytes = Data([0, 0, 0, 99, 109, 111, 111, 118, 0])
            try bytes.write(to: directory.appendingPathComponent("rgb.mp4"))
            let manifestURL = directory.appendingPathComponent("manifest.json")
            var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
            var inventory = manifest["fileInventory"] as! [[String: Any]]
            let index = inventory.firstIndex { $0["path"] as? String == "rgb.mp4" }!
            inventory[index]["bytes"] = bytes.count
            inventory[index]["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            manifest["fileInventory"] = inventory
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        }
        defer { try? fileManager.removeItem(at: truncated) }
        try expectRejection("truncated source movie") {
            _ = try writer.archiveSession(folderPath: truncated.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let oversized = try changedSession { directory in
            let sparse = directory.appendingPathComponent("too-large.bin")
            guard fileManager.createFile(atPath: sparse.path, contents: nil) else { throw failure("Cannot create sparse fixture") }
            let handle = try FileHandle(forWritingTo: sparse)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(UInt32.max))
        }
        defer { try? fileManager.removeItem(at: oversized) }
        try expectRejection("4 GiB source boundary") {
            _ = try writer.archiveSession(folderPath: oversized.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
        }
        let metadataBoundary = try changedSession { directory in
            // Whitespace grows the source log without generating a huge YAML
            // value or millions of records. The exact 32 MiB boundary is valid.
            let location = directory.appendingPathComponent("frames.jsonl")
            var data = try Data(contentsOf: location)
            data.append(Data(repeating: 32, count: 32 * 1024 * 1024 - data.count))
            try data.write(to: location)
            let manifestURL = directory.appendingPathComponent("manifest.json")
            var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
            var inventory = manifest["fileInventory"] as! [[String: Any]]
            let index = inventory.firstIndex { $0["path"] as? String == "frames.jsonl" }!
            inventory[index]["bytes"] = data.count
            inventory[index]["sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            manifest["fileInventory"] = inventory
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        }
        defer { try? fileManager.removeItem(at: metadataBoundary) }
        let boundaryResult = try writer.archiveSession(folderPath: metadataBoundary.path, allowedSessionsRoot: root,
                                                       destinationDirectory: output)
        try fileManager.removeItem(at: boundaryResult.url)
        let boundaryHandle = try FileHandle(forWritingTo: metadataBoundary.appendingPathComponent("frames.jsonl"))
        try boundaryHandle.truncate(atOffset: 32 * 1024 * 1024 + 1)
        try boundaryHandle.close()
        let boundaryManifestURL = metadataBoundary.appendingPathComponent("manifest.json")
        var boundaryManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: boundaryManifestURL)) as! [String: Any]
        var boundaryInventory = boundaryManifest["fileInventory"] as! [[String: Any]]
        let boundaryIndex = boundaryInventory.firstIndex { $0["path"] as? String == "frames.jsonl" }!
        boundaryInventory[boundaryIndex]["bytes"] = 32 * 1024 * 1024 + 1
        boundaryManifest["fileInventory"] = boundaryInventory
        try JSONSerialization.data(withJSONObject: boundaryManifest).write(to: boundaryManifestURL)
        do {
            _ = try writer.archiveSession(folderPath: metadataBoundary.path, allowedSessionsRoot: root,
                                         destinationDirectory: output)
            throw failure("Expected rejection above the 32 MiB metadata boundary")
        } catch SessionMP4Writer.ExportError.limit(let reason) {
            guard reason == "each source metadata file must be at most 32 MiB" else { throw failure(reason) }
        }
        let counterRecords: [[String: Any]] = [
            ["type": "counter", "unicode": "Tag 4 — café 🦀\nquote: \"yes\" / slash \\",
             "empty": ["mapping": [String: Any](), "sequence": [Any](), "null": NSNull()],
             "nested": [["values": [true, false, NSNull(), ["inner": "日本語"]] as [Any]], ["empty": [Any]()]],
             "numbers": [Int64.min, UInt64.max, -0.0, 0, 1.0, Double.pi, Double.leastNonzeroMagnitude,
                         Double.greatestFiniteMagnitude, NSDecimalNumber(string: "123456789012345678901234567890.125")] as [Any]],
            [:],
            ["array": [[1, 2], [3], []], "escaped\nkey": "\t\r\n"],
        ]
        var counterSourceData = Data(), expectedYAMLBytes: Int64 = 0
        for object in counterRecords {
            expectedYAMLBytes += try SessionMP4Writer.yamlRecordByteCount(object)
            counterSourceData.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            counterSourceData.append(10)
        }
        let counterSession = try changedSession { directory in
            try counterSourceData.write(to: directory.appendingPathComponent("events.jsonl"))
            let manifestURL = directory.appendingPathComponent("manifest.json")
            var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
            var inventory = manifest["fileInventory"] as! [[String: Any]]
            let index = inventory.firstIndex { $0["path"] as? String == "events.jsonl" }!
            inventory[index]["bytes"] = counterSourceData.count
            inventory[index]["sha256"] = SHA256.hash(data: counterSourceData).map { String(format: "%02x", $0) }.joined()
            manifest["fileInventory"] = inventory
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        }
        defer { try? fileManager.removeItem(at: counterSession) }
        let counterResult = try writer.archiveSession(folderPath: counterSession.path, allowedSessionsRoot: root,
                                                      destinationDirectory: output)
        let extractor = Process(), yamlPipe = Pipe()
        extractor.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        extractor.arguments = ["ffmpeg", "-v", "error", "-i", counterResult.url.path,
                               "-map", "0:m:handler_name:afar.events", "-c", "copy", "-f", "data", "pipe:1"]
        extractor.standardOutput = yamlPipe
        try extractor.run()
        let exportedYAML = yamlPipe.fileHandleForReading.readDataToEndOfFile()
        extractor.waitUntilExit()
        guard extractor.terminationStatus == 0, expectedYAMLBytes == Int64(exportedYAML.count) else {
            throw failure("YAML byte counter disagrees with actual exported nested/Unicode/numeric records: \(expectedYAMLBytes) vs \(exportedYAML.count)")
        }
        try fileManager.removeItem(at: counterResult.url)
        try expectRejection("YAML counter non-finite scalar") {
            _ = try SessionMP4Writer.yamlRecordByteCount(["invalid": Double.nan])
        }
        try expectRejection("YAML counter unsupported scalar") {
            _ = try SessionMP4Writer.yamlRecordByteCount(["invalid": Date()])
        }
        var excessiveNesting: [String: Any] = ["leaf": true]
        for _ in 0..<128 { excessiveNesting = ["child": excessiveNesting] }
        try expectRejection("YAML counter depth boundary") {
            _ = try SessionMP4Writer.yamlRecordByteCount(excessiveNesting)
        }
        let remaining = try fileManager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
        guard Set(remaining.map(\.lastPathComponent)) == completedExports,
              remaining.allSatisfy({ $0.pathExtension == "mp4" }) else {
            throw failure("Failed exports left partial output files")
        }
        print("PASS: native MP4 byte count, unique file-URL export, finalized/inventory checks, source containment, link/path rejection, truncated movie, exact YAML record counting, 32 MiB metadata boundary and 4 GiB boundary rejection.")
    }

    private static func expectRejection(_ reason: String, _ action: () throws -> Void) throws {
        do {
            try action()
            throw failure("Expected rejection: \(reason)")
        } catch let error as NSError where error.domain == "ValidateMP4" {
            throw error
        } catch {
            print("Rejected \(reason): \(error.localizedDescription)")
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ValidateMP4", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
