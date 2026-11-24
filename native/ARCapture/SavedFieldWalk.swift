import Foundation
import CryptoKit
import Darwin

/// A summary is independently shareable, including when MP4 preparation failed.
struct SavedFieldWalk {
    let url: URL
    let manifest: [String: Any]
    let data: Data
    let summary: [String: Any]
    var text: String { String(decoding: data, as: UTF8.self) }
    var descriptor: [String: Any] {
        ["url": url.absoluteString, "path": url.path, "bytes": data.count,
         "format": "yaml", "mimeType": "application/yaml"]
    }

    static func load(id: String, sessionsRoot: URL) throws -> Self {
        guard UUID(uuidString: id) != nil else { throw CaptureError.message("Invalid saved session identifier.") }
        let root = sessionsRoot.standardizedFileURL.resolvingSymlinksInPath()
        let folder = root.appendingPathComponent(id, isDirectory: true)
        let directory = Darwin.open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw CaptureError.message("The saved walk folder is unavailable.") }
        defer { Darwin.close(directory) }
        let manifestData = try read("manifest.json", directory: directory, limit: RecordingCapacity.metadataBytes)
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              manifest["finalized"] as? Bool == true else { throw CaptureError.message("Stop and save the walk before sharing its YAML.") }
        let data = try read("field-walk-summary.yaml", directory: directory, limit: RecordingCapacity.summaryBytes)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let matches = (manifest["fileInventory"] as? [[String: Any]] ?? []).filter { $0["path"] as? String == "field-walk-summary.yaml" }
        guard matches.count == 1, let entry = matches.first,
              (entry["bytes"] as? NSNumber)?.int64Value == Int64(data.count), entry["sha256"] as? String == digest,
              let text = String(data: data, encoding: .utf8) else { throw CaptureError.message("Saved field summary failed its integrity check.") }
        let summary = try FieldTextCodec.parse(text, maximumBytes: Int(RecordingCapacity.summaryBytes))
        return Self(url: folder.appendingPathComponent("field-walk-summary.yaml"), manifest: manifest, data: data, summary: summary)
    }

    private static func read(_ name: String, directory: Int32, limit: Int64) throws -> Data {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw CaptureError.message("Saved walk \(name) is unavailable.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size >= 0, before.st_size <= limit else { throw CaptureError.message("Saved walk \(name) exceeds its size limit or is not a regular file.") }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard Int64(data.count + chunk.count) <= limit else { throw CaptureError.message("Saved walk metadata changed or exceeded its size limit.") }
            data.append(chunk)
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size, data.count == Int(after.st_size),
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw CaptureError.message("Saved walk metadata changed while opening.") }
        return data
    }
}
