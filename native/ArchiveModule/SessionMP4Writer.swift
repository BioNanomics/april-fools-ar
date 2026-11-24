import Foundation
import CryptoKit
import CoreFoundation
import Darwin

/// Self-contained schema-1 MP4 transport. Camera/video and all original sidecars
/// are preserved; only bounded JSON/YAML and the movie index are held in memory.
struct SessionMP4Writer {
    struct Result { let url: URL; let bytes: UInt64 }

    enum ExportError: LocalizedError {
        case invalidSource(String), invalidEntry(String), unsupportedMovie(String)
        case sourceChanged(String), integrity(String), limit(String), cannotCreate, cancelled
        var errorDescription: String? {
            switch self {
            case .invalidSource(let reason): return "Invalid session folder: \(reason)"
            case .invalidEntry(let name): return "Unsupported recording entry: \(name)"
            case .unsupportedMovie(let reason): return "Unsupported source MP4: \(reason)"
            case .sourceChanged(let name): return "Session changed during export: \(name). Stop and finalize it before exporting."
            case .integrity(let name): return "Recording integrity check failed: \(name)"
            case .limit(let reason): return "Recording export limit: \(reason)"
            case .cannotCreate: return "Unable to create the MP4 recording."
            case .cancelled: return "Recording export was cancelled."
            }
        }
    }

    private struct Entry {
        let url: URL, name: String, directory: Bool, bytes: UInt64
        let modified: Date, inode: UInt64, device: UInt64
    }
    private struct Expected { let bytes: UInt64; let sha256: String }
    private struct Atom {
        let type: String, offset: Int, size: Int, header: Int
        var payload: Int { offset + header }
        var end: Int { offset + size }
    }
    private struct Movie {
        let bytes: Data, sourceOffset: UInt64, children: [Atom], mvhd: Atom
        let timescale: UInt32, duration: UInt32, trackID: UInt32
    }

    private static let maximum = UInt64(UInt32.max) // Strictly below 4 GiB.
    private static let jsonLimit = 32 * 1024 * 1024
    private static let yamlLimit = 64 * 1024 * 1024
    private static let movieLimit = 64 * 1024 * 1024
    private static let entryLimit = 65_534
    private static let chunkBytes = 64 * 1024
    private static let trackNames = ["afar.session", "afar.frames", "afar.events", "afar.files"]
    private static let filesURI = "urn:april-fools-ar:recording:1:files:tar"

    /// Production callers inject Documents/AprilFoolsAR/sessions. Other roots are
    /// supported for host validation; only one direct UUID child may be exported.
    /// An optional affine playback transform changes only the visible track in the
    /// replacement movie index; exact restoration retains the original source movie.
    func archiveSession(folderPath: String, allowedSessionsRoot: URL,
                        destinationDirectory: URL, playbackTransform: [Double]? = nil,
                        shouldCancel: () -> Bool = { false }) throws -> Result {
        try Self.checkCancellation(shouldCancel)
        let source = try validatedSource(folderPath, root: allowedSessionsRoot)
        let entries = try collectEntries(in: source, shouldCancel: shouldCancel)
        let files = Dictionary(uniqueKeysWithValues: entries.filter { !$0.directory }.map { ($0.name, $0) })
        func required(_ name: String) throws -> Entry {
            guard let entry = files[name] else { throw ExportError.invalidSource("missing \(name)") }
            return entry
        }
        let manifestEntry = try required("manifest.json")
        let manifestData = try readMetadata(manifestEntry, inside: source, shouldCancel: shouldCancel)
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let finalized = manifest["finalized"] as? NSNumber,
              CFGetTypeID(finalized) == CFBooleanGetTypeID(), finalized.boolValue else {
            throw ExportError.invalidSource("a fully finalized manifest is required")
        }
        var expected = try sourceInventory(manifest, files: files)
        expected["manifest.json"] = Expected(bytes: UInt64(manifestData.count), sha256: Self.hash(manifestData))
        let videoEntry = try required("rgb.mp4")
        let movie = try readMovie(videoEntry, inside: source, shouldCancel: shouldCancel)
        let framesData = try readMetadata(required("frames.jsonl"), inside: source, shouldCancel: shouldCancel)
        let eventsData = try readMetadata(required("events.jsonl"), inside: source, shouldCancel: shouldCancel)
        try check(framesData, against: expected["frames.jsonl"], name: "frames.jsonl")
        try check(eventsData, against: expected["events.jsonl"], name: "events.jsonl")
        let frames = try Self.yamlRecords(framesData, shouldCancel: shouldCancel)
        let events = try Self.yamlRecords(eventsData, shouldCancel: shouldCancel)
        let sidecars = entries.filter { $0.name != "rgb.mp4" }
        let predictedTarBytes = try Self.checkedSum(sidecars.map {
            512 + $0.bytes + (512 - $0.bytes % 512) % 512
        } + [1024])
        // Reject an impossible final size before hashing several GiB of inputs.
        _ = try Self.checkedSum([videoEntry.bytes, predictedTarBytes, UInt64(frames.count),
                                 UInt64(events.count), UInt64(movie.bytes.count), 8])

        // Compute the TAR digest without a temporary TAR copy. The same bounded
        // stream is written below and checked again before the MP4 is published.
        var tarHasher = SHA256(), tarBytes: UInt64 = 0
        try streamTar(sidecars, inside: source, expected: expected, shouldCancel: shouldCancel) { data in
            tarHasher.update(data: data); tarBytes += UInt64(data.count)
            guard tarBytes < Self.maximum else { throw ExportError.limit("exports must remain below 4 GiB") }
        }
        let tarSHA = Self.hex(tarHasher.finalize())
        guard tarBytes == predictedTarBytes else { throw ExportError.integrity("unexpected TAR length") }
        let videoSHA = try hashFile(videoEntry, inside: source, shouldCancel: shouldCancel)
        guard let expectedVideo = expected["rgb.mp4"], expectedVideo.sha256 == videoSHA else {
            throw ExportError.integrity("rgb.mp4 does not match its original manifest")
        }
        let payloads: [String: Any] = [
            "afar.frames": Self.payload(frames, mime: "application/yaml"),
            "afar.events": Self.payload(events, mime: "application/yaml"),
            "afar.files": ["bytes": tarBytes, "sha256": tarSHA, "mimeType": "application/x-tar"]
        ]
        var envelope: [String: Any] = [
            "format": "april-fools-ar-recording", "version": 1, "draft": false,
            "session": manifest,
            "sourceVideo": ["bytes": videoEntry.bytes, "sha256": videoSHA, "moovOffset": movie.sourceOffset],
            "payloads": payloads
        ]
        if let playbackTransform { envelope["playbackTransform"] = playbackTransform }
        var sessionYAML = YAMLBuffer(limit: Self.yamlLimit)
        try sessionYAML.emit(envelope)
        let metadata = [sessionYAML.data, frames, events]
        let payloadSizes = metadata.map { UInt64($0.count) } + [tarBytes]
        let mdatSize = try Self.checkedSum(payloadSizes + [8])
        let replacement = try replacementMovie(movie, payloadSizes: payloadSizes,
                                               firstOffset: videoEntry.bytes + 8,
                                               playbackTransform: playbackTransform)
        let total = try Self.checkedSum([videoEntry.bytes, mdatSize, UInt64(replacement.count)])

        let manager = FileManager.default
        try manager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let basename = "AprilFoolsAR-\(source.lastPathComponent)-\(UUID().uuidString)"
        let destination = destinationDirectory.appendingPathComponent(basename + ".mp4")
        let temporary = destinationDirectory.appendingPathComponent("." + basename + ".partial")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ExportError.cannotCreate }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var succeeded = false, written: UInt64 = 0
        defer {
            try? output.close()
            if !succeeded { try? manager.removeItem(at: temporary) }
        }
        func append(_ data: Data) throws {
            try Self.checkCancellation(shouldCancel)
            guard UInt64(data.count) < Self.maximum, written < Self.maximum - UInt64(data.count) else {
                throw ExportError.limit("exports must remain below 4 GiB")
            }
            try output.write(contentsOf: data); written += UInt64(data.count)
        }

        var copiedVideoHasher = SHA256(), copyOffset: UInt64 = 0
        try streamFile(videoEntry, inside: source, shouldCancel: shouldCancel) { chunk in
            copiedVideoHasher.update(data: chunk)
            var patched = chunk
            let typeStart = movie.sourceOffset + 4
            for index in 0..<4 {
                let absolute = typeStart + UInt64(index)
                if absolute >= copyOffset && absolute < copyOffset + UInt64(chunk.count) {
                    patched[Int(absolute - copyOffset)] = Array("free".utf8)[index]
                }
            }
            try append(patched); copyOffset += UInt64(chunk.count)
        }
        guard Self.hex(copiedVideoHasher.finalize()) == videoSHA else { throw ExportError.sourceChanged("rgb.mp4") }
        var mdatHeader = Data(); mdatHeader.mp4U32(UInt32(mdatSize)); mdatHeader.append(Data("mdat".utf8))
        try append(mdatHeader)
        for data in metadata { try append(data) }
        var copiedTarHasher = SHA256()
        try streamTar(sidecars, inside: source, expected: expected, shouldCancel: shouldCancel) { data in
            copiedTarHasher.update(data: data); try append(data)
        }
        guard Self.hex(copiedTarHasher.finalize()) == tarSHA else { throw ExportError.sourceChanged("sidecar archive") }
        try append(replacement)
        guard written == total else { throw ExportError.integrity("unexpected final MP4 length") }
        let finalEntries = try collectEntries(in: source, shouldCancel: shouldCancel)
        guard finalEntries.map(\.name) == entries.map(\.name) else { throw ExportError.sourceChanged("session contents") }
        for entry in entries {
            try Self.checkCancellation(shouldCancel)
            try verifyEntry(entry, inside: source)
        }
        try output.synchronize(); try output.close()
        try Self.checkCancellation(shouldCancel)
        try manager.moveItem(at: temporary, to: destination)
        succeeded = true
        return Result(url: destination, bytes: written)
    }

    // MARK: Source identity, containment and integrity

    private static func checkCancellation(_ shouldCancel: () -> Bool) throws {
        if shouldCancel() { throw ExportError.cancelled }
    }

    private func validatedSource(_ folderPath: String, root: URL) throws -> URL {
        let decoded = folderPath.removingPercentEncoding ?? folderPath
        guard !decoded.contains("\0"), !decoded.split(separator: "/").contains("..") else {
            throw ExportError.invalidSource("path traversal is not allowed")
        }
        let supplied: URL
        if folderPath.hasPrefix("file:") {
            guard let url = URL(string: folderPath), url.isFileURL,
                  url.host == nil || url.host == "" || url.host == "localhost" else {
                throw ExportError.invalidSource("expected a local file URL")
            }
            supplied = url
        } else {
            guard folderPath.hasPrefix("/") else { throw ExportError.invalidSource("expected an absolute path") }
            supplied = URL(fileURLWithPath: folderPath, isDirectory: true)
        }
        let source = supplied.standardizedFileURL
        let canonicalRoot = try canonicalURL(root), canonicalSource = try canonicalURL(source)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              UUID(uuidString: source.lastPathComponent) != nil,
              try canonicalURL(source.deletingLastPathComponent()).path == canonicalRoot.path,
              canonicalSource.deletingLastPathComponent().path == canonicalRoot.path else {
            throw ExportError.invalidSource("select one UUID directory directly inside the sessions folder")
        }
        return canonicalSource
    }

    private func canonicalURL(_ url: URL) throws -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try resolved.resourceValues(forKeys: [.canonicalPathKey])
        return URL(fileURLWithPath: values.canonicalPath ?? resolved.path)
    }

    private func collectEntries(in source: URL, shouldCancel: () -> Bool) throws -> [Entry] {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil,
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw ExportError.invalidSource("unable to enumerate files")
        }
        var result: [Entry] = [], names = Set<String>(), totalBytes: UInt64 = 0
        let prefix = source.path + "/"
        for case let url as URL in enumerator {
            try Self.checkCancellation(shouldCancel)
            guard url.path.hasPrefix(prefix) else { throw ExportError.invalidEntry(url.lastPathComponent) }
            let name = String(url.path.dropFirst(prefix.count))
            try Self.safePath(name)
            guard names.insert(Self.pathKey(name)).inserted else { throw ExportError.invalidEntry("colliding path: \(name)") }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == .typeRegular || type == .typeDirectory else { throw ExportError.invalidEntry(name) }
            let directory = type == .typeDirectory
            let size = directory ? 0 : (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard size < Self.maximum else { throw ExportError.limit("source files must remain below 4 GiB") }
            totalBytes = try Self.checkedSum([totalBytes, size])
            guard let modified = attributes[.modificationDate] as? Date,
                  let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
                  let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value else {
                throw ExportError.invalidEntry(name)
            }
            if Self.pathKey(name) == "rgb.mp4" && (name != "rgb.mp4" || directory) {
                throw ExportError.invalidEntry("rgb.mp4 is a reserved regular-file name")
            }
            result.append(Entry(url: url, name: name, directory: directory, bytes: size,
                                modified: modified, inode: inode, device: device))
            guard result.count <= Self.entryLimit else { throw ExportError.limit("at most 65,534 entries are supported") }
        }
        if let error = enumerationError { throw error }
        return result.sorted { $0.name < $1.name }
    }

    private static func safePath(_ name: String) throws {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              name.utf8.count <= 256 else { throw ExportError.invalidEntry(name) }
        _ = try tarNames(name)
    }
    private static func pathKey(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }

    private func verifyEntry(_ entry: Entry, inside source: URL) throws {
        let canonical = try canonicalURL(entry.url)
        let attributes = try FileManager.default.attributesOfItem(atPath: entry.url.path)
        let type: FileAttributeType = entry.directory ? .typeDirectory : .typeRegular
        guard canonical.path == entry.url.path, canonical.path.hasPrefix(source.path + "/"),
              attributes[.type] as? FileAttributeType == type,
              (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == entry.inode,
              (attributes[.systemNumber] as? NSNumber)?.uint64Value == entry.device,
              (attributes[.modificationDate] as? Date) == entry.modified,
              entry.directory || (attributes[.size] as? NSNumber)?.uint64Value == entry.bytes else {
            throw ExportError.sourceChanged(entry.name)
        }
    }

    private func openEntry(_ entry: Entry, inside source: URL) throws -> FileHandle {
        try verifyEntry(entry, inside: source)
        let fd = Darwin.open(entry.url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw ExportError.sourceChanged(entry.name) }
        var status = stat()
        guard fstat(fd, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG,
              UInt64(status.st_ino) == entry.inode, UInt64(status.st_dev) == entry.device,
              status.st_size >= 0, UInt64(status.st_size) == entry.bytes else {
            Darwin.close(fd); throw ExportError.sourceChanged(entry.name)
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private func streamFile(_ entry: Entry, inside source: URL, shouldCancel: () -> Bool,
                            consume: (Data) throws -> Void) throws {
        try Self.checkCancellation(shouldCancel)
        let input = try openEntry(entry, inside: source)
        defer { try? input.close() }
        var read: UInt64 = 0
        // FileHandle's Foundation buffers must drain per chunk, including the
        // consumer's temporaries, rather than surviving the whole export.
        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let data = try input.read(upToCount: Self.chunkBytes), !data.isEmpty else { return false }
            try Self.checkCancellation(shouldCancel)
            read += UInt64(data.count)
            guard read <= entry.bytes else { throw ExportError.sourceChanged(entry.name) }
            try consume(data)
            return true
        }) {}
        guard read == entry.bytes else { throw ExportError.sourceChanged(entry.name) }
        try verifyEntry(entry, inside: source)
    }
    private func readMetadata(_ entry: Entry, inside source: URL, shouldCancel: () -> Bool) throws -> Data {
        guard entry.bytes <= UInt64(Self.jsonLimit) else { throw ExportError.limit("each source metadata file must be at most 32 MiB") }
        var result = Data(); result.reserveCapacity(Int(entry.bytes))
        try streamFile(entry, inside: source, shouldCancel: shouldCancel) { result.append($0) }
        return result
    }
    private func hashFile(_ entry: Entry, inside source: URL, shouldCancel: () -> Bool) throws -> String {
        var hasher = SHA256()
        try streamFile(entry, inside: source, shouldCancel: shouldCancel) { hasher.update(data: $0) }
        return Self.hex(hasher.finalize())
    }
    private static func hash(_ data: Data) -> String { hex(SHA256.hash(data: data)) }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    private func sourceInventory(_ manifest: [String: Any], files: [String: Entry]) throws -> [String: Expected] {
        guard let inventory = manifest["fileInventory"] as? [[String: Any]], inventory.count <= Self.entryLimit else {
            throw ExportError.integrity("a complete original fileInventory is required")
        }
        var expected: [String: Expected] = [:], names = Set<String>()
        for item in inventory {
            guard let name = item["path"] as? String,
                  let count = item["bytes"] as? NSNumber, CFGetTypeID(count) != CFBooleanGetTypeID(),
                  count.doubleValue.isFinite, count.doubleValue >= 0,
                  count.doubleValue == Double(count.uint64Value),
                  let sha = item["sha256"] as? String, sha.utf8.count == 64,
                  sha.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ExportError.integrity("invalid original file inventory entry")
            }
            try Self.safePath(name)
            guard name != "manifest.json", names.insert(Self.pathKey(name)).inserted,
                  let file = files[name], file.bytes == count.uint64Value else {
                throw ExportError.integrity("missing, duplicate or wrong-size file: \(name)")
            }
            expected[name] = Expected(bytes: count.uint64Value, sha256: sha)
        }
        guard Set(expected.keys) == Set(files.keys.filter { $0 != "manifest.json" }) else {
            throw ExportError.integrity("source inventory does not cover every original file")
        }
        return expected
    }
    private func check(_ data: Data, against expected: Expected?, name: String) throws {
        guard let expected, expected.bytes == UInt64(data.count), expected.sha256 == Self.hash(data) else {
            throw ExportError.integrity(name)
        }
    }

    // MARK: YAML 1.2, JSON-compatible values only

    /// Exact contribution of one native JSONL record to its exported YAML
    /// track, including the document marker. Holds only scalar/line temporaries;
    /// no complete YAML document or extra record-sized JSON buffer is built.
    static func yamlRecordByteCount(_ object: [String: Any]) throws -> Int64 {
        try autoreleasepool {
            var output = YAMLBuffer(limit: yamlLimit, countsOnly: true)
            try output.append("---\n")
            try output.emit(object)
            return Int64(output.byteCount)
        }
    }

    private struct YAMLBuffer {
        var data = Data()
        let limit: Int
        var countsOnly = false
        private(set) var byteCount = 0
        mutating func append(_ text: String) throws {
            let bytes = text.utf8.count
            guard bytes <= limit - byteCount else { throw ExportError.limit("generated YAML must remain at most 64 MiB per track") }
            byteCount += bytes
            if !countsOnly { data.append(contentsOf: text.utf8) }
        }
        private func scalar(_ value: Any) throws -> String {
            if value is NSNull { return "null" }
            if let string = value as? String {
                let encoded = try JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes])
                return String(decoding: encoded, as: UTF8.self)
            }
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
                guard number.doubleValue.isFinite else { throw ExportError.integrity("non-finite JSON number") }
                // NSNumber.stringValue rounds some Double values to 16 digits.
                // JSON's scalar encoder preserves the original binary64 value,
                // and JSON numeric syntax is also valid YAML 1.2 syntax.
                var encoded = try JSONSerialization.data(withJSONObject: number, options: [.fragmentsAllowed])
                if countsOnly {
                    // The native recorder first writes JSON, then export parses
                    // it back. Match that scalar normalization without building
                    // or parsing a second whole-record JSON document. In
                    // particular, native -0.0 is written as -0 and reopens as 0.
                    let reopened = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
                    encoded = try JSONSerialization.data(withJSONObject: reopened, options: [.fragmentsAllowed])
                }
                return String(decoding: encoded, as: UTF8.self)
            }
            if let mapping = value as? [String: Any], mapping.isEmpty { return "{}" }
            if let sequence = value as? [Any], sequence.isEmpty { return "[]" }
            throw ExportError.integrity("unsupported JSON value in YAML")
        }
        private func compound(_ value: Any) -> Bool {
            if let mapping = value as? [String: Any] { return !mapping.isEmpty }
            if let sequence = value as? [Any] { return !sequence.isEmpty }
            return false
        }
        mutating func emit(_ value: Any, indent: Int = 0, depth: Int = 0) throws {
            guard depth < 128 else { throw ExportError.limit("metadata nesting exceeds 128 levels") }
            let pad = String(repeating: " ", count: indent)
            if let mapping = value as? [String: Any], !mapping.isEmpty {
                for key in mapping.keys.sorted() {
                    let child = mapping[key]!
                    try append(pad + scalar(key) + ":")
                    if compound(child) { try append("\n"); try emit(child, indent: indent + 2, depth: depth + 1) }
                    else { try append(" " + scalar(child) + "\n") }
                }
            } else if let sequence = value as? [Any], !sequence.isEmpty {
                for child in sequence {
                    try append(pad + "-")
                    if compound(child) { try append("\n"); try emit(child, indent: indent + 2, depth: depth + 1) }
                    else { try append(" " + scalar(child) + "\n") }
                }
            } else { try append(pad + scalar(value) + "\n") }
        }
    }
    private static func yamlRecords(_ data: Data, shouldCancel: () -> Bool) throws -> Data {
        guard String(data: data, encoding: .utf8) != nil else { throw ExportError.integrity("metadata is not UTF-8") }
        var output = YAMLBuffer(limit: yamlLimit), count = 0
        for line in data.split(separator: 10, omittingEmptySubsequences: false) {
            try checkCancellation(shouldCancel)
            let bytes = Data(line)
            if String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            // Drain Foundation's parsing/scalar-encoding temporaries per record;
            // retaining them across a full capture can consume several GiB.
            try autoreleasepool {
                guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                    throw ExportError.integrity("each JSONL record must be an object")
                }
                count += 1
                guard count <= 100_000 else { throw ExportError.limit("at most 100,000 records per metadata stream") }
                try output.append("---\n"); try output.emit(object)
            }
        }
        if count == 0 { try output.append("# No records.\n") }
        return output.data
    }
    private static func payload(_ data: Data, mime: String) -> [String: Any] {
        ["bytes": data.count, "sha256": hash(data), "mimeType": mime]
    }

    // MARK: Streaming POSIX USTAR

    private static func tarNames(_ name: String) throws -> (String, String) {
        if name.utf8.count <= 100 { return (name, "") }
        for slash in name.indices.reversed() where name[slash] == "/" {
            let prefix = String(name[..<slash]), base = String(name[name.index(after: slash)...])
            if prefix.utf8.count <= 155 && base.utf8.count <= 100 { return (base, prefix) }
        }
        throw ExportError.invalidEntry("path does not fit USTAR: \(name)")
    }
    private static func tarHeader(_ entry: Entry) throws -> Data {
        var data = Data(repeating: 0, count: 512)
        let (name, prefix) = try tarNames(entry.name)
        func write(_ text: String, at offset: Int, width: Int) throws {
            let bytes = Data(text.utf8)
            guard bytes.count <= width else { throw ExportError.invalidEntry(entry.name) }
            data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
        func octal(_ value: UInt64, at offset: Int, width: Int) throws {
            let text = String(value, radix: 8)
            guard text.count < width else { throw ExportError.limit("USTAR numeric range") }
            try write(String(repeating: "0", count: width - text.count - 1) + text + "\0", at: offset, width: width)
        }
        try write(name, at: 0, width: 100)
        try octal(entry.directory ? 0o755 : 0o644, at: 100, width: 8)
        try octal(0, at: 108, width: 8); try octal(0, at: 116, width: 8)
        try octal(entry.bytes, at: 124, width: 12); try octal(0, at: 136, width: 12)
        data.replaceSubrange(148..<156, with: Data(repeating: 32, count: 8))
        data[156] = entry.directory ? 53 : 48
        try write("ustar\0", at: 257, width: 6); try write("00", at: 263, width: 2)
        try write(prefix, at: 345, width: 155)
        let checksum = String(data.reduce(UInt64(0)) { $0 + UInt64($1) }, radix: 8)
        guard checksum.count <= 6 else { throw ExportError.invalidEntry(entry.name) }
        try write(String(repeating: "0", count: 6 - checksum.count) + checksum + "\0 ", at: 148, width: 8)
        return data
    }
    private func streamTar(_ entries: [Entry], inside source: URL, expected: [String: Expected],
                           shouldCancel: () -> Bool, consume: (Data) throws -> Void) throws {
        for entry in entries {
            try Self.checkCancellation(shouldCancel)
            try verifyEntry(entry, inside: source)
            try consume(Self.tarHeader(entry))
            if !entry.directory {
                var hash = SHA256()
                try streamFile(entry, inside: source, shouldCancel: shouldCancel) { chunk in hash.update(data: chunk); try consume(chunk) }
                guard let expectation = expected[entry.name], expectation.bytes == entry.bytes,
                      expectation.sha256 == Self.hex(hash.finalize()) else { throw ExportError.integrity(entry.name) }
                let padding = Int((512 - entry.bytes % 512) % 512)
                if padding > 0 { try consume(Data(repeating: 0, count: padding)) }
            }
        }
        try consume(Data(repeating: 0, count: 1024))
    }

    // MARK: Bounded ISO BMFF movie index parsing and metadata-track writing

    private func readMovie(_ entry: Entry, inside source: URL, shouldCancel: () -> Bool) throws -> Movie {
        let input = try openEntry(entry, inside: source)
        defer { try? input.close() }
        var offset: UInt64 = 0, top: [(String, UInt64, UInt64, Int)] = []
        while offset < entry.bytes {
            try Self.checkCancellation(shouldCancel)
            guard entry.bytes - offset >= 8 else { throw ExportError.unsupportedMovie("truncated top-level box") }
            try input.seek(toOffset: offset)
            let header = try Self.exactRead(input, count: 8)
            var size = UInt64(try header.mp4Read32(0)), headerSize = 8
            if size == 1 { size = try Self.exactRead(input, count: 8).mp4Read64(0); headerSize = 16 }
            guard size >= UInt64(headerSize), size <= entry.bytes - offset else { throw ExportError.unsupportedMovie("invalid or open-ended box size") }
            let type = String(decoding: header[4..<8], as: UTF8.self)
            top.append((type, offset, size, headerSize)); offset += size
            guard top.count <= 16_384 else { throw ExportError.unsupportedMovie("too many boxes") }
        }
        guard top.first?.0 == "ftyp", top.filter({ $0.0 == "moov" }).count == 1,
              top.contains(where: { $0.0 == "mdat" }),
              !top.contains(where: { ["moof", "mfra", "sidx", "styp"].contains($0.0) }),
              let index = top.first(where: { $0.0 == "moov" }), index.2 <= UInt64(Self.movieLimit) else {
            throw ExportError.unsupportedMovie("requires one ordinary movie box (at most 64 MiB), without fragmentation")
        }
        try input.seek(toOffset: index.1)
        let data = try Self.exactRead(input, count: Int(index.2))
        let root = try Self.atoms(data, from: 0, to: data.count)
        guard root.count == 1, root[0].type == "moov" else { throw ExportError.unsupportedMovie("invalid movie box") }
        let children = try Self.atoms(data, from: root[0].payload, to: root[0].end)
        guard !children.contains(where: { ["mvex", "cmov"].contains($0.type) }) else {
            throw ExportError.unsupportedMovie("compressed/fragmented movies are not supported")
        }
        let mvhd = try Self.one(children, "mvhd")
        let version = try Self.version(data, mvhd)
        let time = mvhd.payload + (version == 1 ? 20 : 12)
        let timescale = try data.mp4Read32(time)
        let duration64 = version == 1 ? try data.mp4Read64(time + 4) : UInt64(try data.mp4Read32(time + 4))
        guard mvhd.size >= mvhd.header + (version == 1 ? 112 : 100), timescale > 0,
              duration64 > 0, duration64 <= UInt64(UInt32.max) else {
            throw ExportError.unsupportedMovie("unsupported movie timescale/duration")
        }
        let tracks = children.filter { $0.type == "trak" }
        guard tracks.count == 1 else { throw ExportError.unsupportedMovie("requires exactly one H.264 camera track") }
        let track = tracks[0], trackChildren = try Self.atoms(data, from: track.payload, to: track.end)
        let tkhd = try Self.one(trackChildren, "tkhd"), trackVersion = try Self.version(data, tkhd)
        let trackID = try data.mp4Read32(tkhd.payload + (trackVersion == 1 ? 20 : 12))
        guard trackID > 0, trackID < UInt32.max - 5 else { throw ExportError.unsupportedMovie("invalid track ID") }
        let mdia = try Self.one(trackChildren, "mdia")
        let media = try Self.atoms(data, from: mdia.payload, to: mdia.end)
        let hdlr = try Self.one(media, "hdlr")
        guard hdlr.size >= hdlr.header + 24,
              String(decoding: data[(hdlr.payload + 8)..<(hdlr.payload + 12)], as: UTF8.self) == "vide" else {
            throw ExportError.unsupportedMovie("requires a camera video handler")
        }
        let minf = try Self.one(media, "minf"), minfChildren = try Self.atoms(data, from: minf.payload, to: minf.end)
        let dinf = try Self.one(minfChildren, "dinf")
        let dref = try Self.one(Self.atoms(data, from: dinf.payload, to: dinf.end), "dref")
        guard try data.mp4Read32(dref.payload) == 0, try data.mp4Read32(dref.payload + 4) == 1 else {
            throw ExportError.unsupportedMovie("external data references are not supported")
        }
        let references = try Self.atoms(data, from: dref.payload + 8, to: dref.end)
        guard references.count == 1, references[0].type == "url ", references[0].size == references[0].header + 4,
              try data.mp4Read32(references[0].payload) == 1 else {
            throw ExportError.unsupportedMovie("external data references are not supported")
        }
        let stbl = try Self.one(minfChildren, "stbl")
        let stsd = try Self.one(Self.atoms(data, from: stbl.payload, to: stbl.end), "stsd")
        guard try data.mp4Read32(stsd.payload) == 0, try data.mp4Read32(stsd.payload + 4) == 1 else {
            throw ExportError.unsupportedMovie("requires one H.264 sample description")
        }
        let descriptions = try Self.atoms(data, from: stsd.payload + 8, to: stsd.end)
        guard descriptions.count == 1, ["avc1", "avc3"].contains(descriptions[0].type),
              descriptions[0].size >= descriptions[0].header + 8,
              try data.mp4Read16(descriptions[0].payload + 6) == 1 else {
            throw ExportError.unsupportedMovie("requires one self-contained H.264 sample description")
        }
        try verifyEntry(entry, inside: source)
        return Movie(bytes: data, sourceOffset: index.1, children: children, mvhd: mvhd,
                     timescale: timescale, duration: UInt32(duration64), trackID: trackID)
    }

    private static func exactRead(_ input: FileHandle, count: Int) throws -> Data {
        var result = Data(); result.reserveCapacity(count)
        while result.count < count {
            guard let data = try input.read(upToCount: count - result.count), !data.isEmpty else {
                throw ExportError.unsupportedMovie("truncated file")
            }
            result.append(data)
        }
        return result
    }
    private static func atoms(_ data: Data, from start: Int, to end: Int) throws -> [Atom] {
        guard start >= 0, start <= end, end <= data.count else { throw ExportError.unsupportedMovie("box outside its parent") }
        var result: [Atom] = [], offset = start
        while offset < end {
            guard end - offset >= 8 else { throw ExportError.unsupportedMovie("truncated box header") }
            var size = UInt64(try data.mp4Read32(offset)), header = 8
            if size == 1 { guard end - offset >= 16 else { throw ExportError.unsupportedMovie("truncated extended box") }; size = try data.mp4Read64(offset + 8); header = 16 }
            guard size >= UInt64(header), size <= UInt64(end - offset) else { throw ExportError.unsupportedMovie("invalid/open-ended box size") }
            result.append(Atom(type: String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self),
                               offset: offset, size: Int(size), header: header))
            offset += Int(size)
            guard result.count <= 16_384 else { throw ExportError.unsupportedMovie("too many movie boxes") }
        }
        return result
    }
    private static func one(_ atoms: [Atom], _ type: String) throws -> Atom {
        let matches = atoms.filter { $0.type == type }
        guard matches.count == 1 else { throw ExportError.unsupportedMovie("expected one \(type) box") }
        return matches[0]
    }
    private static func version(_ data: Data, _ atom: Atom) throws -> UInt8 {
        guard atom.size >= atom.header + 4, data[atom.payload] <= 1 else { throw ExportError.unsupportedMovie("unsupported \(atom.type) version") }
        return data[atom.payload]
    }
    private static func checkedSum(_ values: [UInt64]) throws -> UInt64 {
        var total: UInt64 = 0
        for value in values {
            guard value < maximum, total < maximum - value else { throw ExportError.limit("exports must remain below 4 GiB") }
            total += value
        }
        return total
    }
    private static func box(_ type: String, _ payload: Data) throws -> Data {
        let size = try checkedSum([8, UInt64(payload.count)])
        var result = Data(); result.mp4U32(UInt32(size)); result.append(Data(type.utf8)); result.append(payload)
        return result
    }
    private static func full(_ type: String, _ payload: Data, flags: UInt32 = 0) throws -> Data {
        var contents = Data(); contents.mp4U32(flags); contents.append(payload)
        return try box(type, contents)
    }
    private func replacementMovie(_ movie: Movie, payloadSizes: [UInt64], firstOffset: UInt64,
                                  playbackTransform: [Double]?) throws -> Data {
        var contents = Data()
        for child in movie.children {
            var original = movie.bytes.subdata(in: child.offset..<child.end)
            if child.type == "mvhd" { original.mp4Set32(movie.trackID + 5, at: original.count - 4) }
            if child.type == "trak", let playbackTransform {
                original = try Self.applyingPlaybackTransform(playbackTransform, to: original)
            }
            contents.append(original)
        }
        var offset = firstOffset
        for index in 0..<4 {
            guard offset < Self.maximum, payloadSizes[index] > 0, payloadSizes[index] < Self.maximum else {
                throw ExportError.limit("payloads and absolute offsets must remain below 4 GiB")
            }
            contents.append(try metadataTrack(movie.trackID + UInt32(index) + 1, name: Self.trackNames[index],
                bytes: UInt32(payloadSizes[index]), offset: UInt32(offset), movie: movie))
            offset += payloadSizes[index]
            guard offset < Self.maximum else { throw ExportError.limit("exports must remain below 4 GiB") }
        }
        guard contents.count <= Self.movieLimit else { throw ExportError.limit("replacement movie index exceeds 64 MiB") }
        return try Self.box("moov", contents)
    }

    private static func applyingPlaybackTransform(_ affine: [Double], to track: Data) throws -> Data {
        guard affine.count == 6, affine.allSatisfy(\.isFinite) else {
            throw ExportError.unsupportedMovie("playback transform must contain six finite affine values")
        }
        func fixed(_ value: Double) throws -> UInt32 {
            let scaled = (value * 65536).rounded()
            guard scaled >= Double(Int32.min), scaled <= Double(Int32.max) else {
                throw ExportError.unsupportedMovie("playback transform exceeds signed 16.16 range")
            }
            return UInt32(bitPattern: Int32(scaled))
        }
        let root = try one(atoms(track, from: 0, to: track.count), "trak")
        let header = try one(atoms(track, from: root.payload, to: root.end), "tkhd")
        let matrixOffset = header.payload + (try version(track, header) == 1 ? 52 : 40)
        guard matrixOffset + 44 <= header.end else {
            throw ExportError.unsupportedMovie("truncated video track matrix")
        }
        let width = Double(try track.mp4Read32(matrixOffset + 36)) / 65536
        let height = Double(try track.mp4Read32(matrixOffset + 40)) / 65536
        let rotations: [[Double]] = [[1, 0, 0, 1, 0, 0], [0, 1, -1, 0, height, 0],
                                     [-1, 0, 0, -1, width, height], [0, -1, 1, 0, 0, width]]
        guard rotations.contains(affine) else {
            throw ExportError.unsupportedMovie("playback transform must be a canonical quarter-turn rotation")
        }
        // ISO BMFF stores [a,b,u,c,d,v,tx,ty,w]. Affine entries are signed
        // 16.16 values; perspective entries u/v/w use signed 2.30 values.
        let matrix: [UInt32] = [try fixed(affine[0]), try fixed(affine[1]), 0,
                                try fixed(affine[2]), try fixed(affine[3]), 0,
                                try fixed(affine[4]), try fixed(affine[5]), 0x40000000]
        var result = track
        for (index, value) in matrix.enumerated() { result.mp4Set32(value, at: matrixOffset + index * 4) }
        return result
    }
    private func metadataTrack(_ id: UInt32, name: String, bytes: UInt32, offset: UInt32, movie: Movie) throws -> Data {
        // An MP4 sample is an AVPacket when FFmpeg demuxes it. Split the TAR
        // into bounded packets so a multi-GiB session never becomes one giant
        // packet, while raw-data extraction still concatenates the exact TAR.
        let sampleLimit: UInt64 = name == "afar.files" ? 1024 * 1024 : UInt64(bytes)
        let sampleCount = UInt32((UInt64(bytes) + sampleLimit - 1) / sampleLimit)
        var mediaTimescale = UInt64(movie.timescale) * UInt64(sampleCount)
        var sampleDelta = UInt64(movie.duration)
        if mediaTimescale > UInt64(UInt32.max) {
            // Reduce the same rational timebase before rejecting unusual source
            // timescales. N equal samples must still span the original movie.
            var a = mediaTimescale, b = sampleDelta
            while b != 0 { let remainder = a % b; a = b; b = remainder }
            mediaTimescale /= a; sampleDelta /= a
        }
        guard mediaTimescale > 0, mediaTimescale <= UInt64(UInt32.max),
              sampleDelta > 0, sampleDelta <= UInt64(UInt32.max) else {
            throw ExportError.unsupportedMovie("metadata sample timebase exceeds uint32")
        }
        let mediaDuration = sampleDelta * UInt64(sampleCount)
        var matrix = Data(); for value: UInt32 in [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000] { matrix.mp4U32(value) }
        var trackHeader = Data()
        for value: UInt32 in [0, 0, id, 0, movie.duration] { trackHeader.mp4U32(value) }
        trackHeader.append(Data(repeating: 0, count: 16)); trackHeader.append(matrix)
        trackHeader.mp4U32(0); trackHeader.mp4U32(0)
        let tkhd = try Self.full("tkhd", trackHeader, flags: 2)
        var mediaHeader = Data()
        let mediaVersion1 = mediaDuration > UInt64(UInt32.max)
        if mediaVersion1 {
            mediaHeader.mp4U64(0); mediaHeader.mp4U64(0)
            mediaHeader.mp4U32(UInt32(mediaTimescale)); mediaHeader.mp4U64(mediaDuration)
        } else {
            for value: UInt32 in [0, 0, UInt32(mediaTimescale), UInt32(mediaDuration)] { mediaHeader.mp4U32(value) }
        }
        mediaHeader.mp4U16(0x55c4); mediaHeader.mp4U16(0)
        let mdhd = try Self.full("mdhd", mediaHeader, flags: mediaVersion1 ? 0x01000000 : 0)
        var handler = Data(repeating: 0, count: 4); handler.append(Data("meta".utf8))
        handler.append(Data(repeating: 0, count: 12)); handler.append(Data((name + "\0").utf8))
        let hdlr = try Self.full("hdlr", handler)
        var reference = Data(); reference.mp4U32(1); reference.append(try Self.full("url ", Data(), flags: 1))
        let dinf = try Self.box("dinf", Self.full("dref", reference))
        var entry = Data(repeating: 0, count: 6); entry.mp4U16(1)
        let sample: Data
        if name == "afar.files" {
            entry.append(try Self.full("uri ", Data((Self.filesURI + "\0").utf8)))
            sample = try Self.box("urim", entry)
        } else {
            entry.append(Data("\0application/yaml\0".utf8)); sample = try Self.box("mett", entry)
        }
        var sampleDescription = Data(); sampleDescription.mp4U32(1); sampleDescription.append(sample)
        let stsd = try Self.full("stsd", sampleDescription)
        func table(_ type: String, _ values: [UInt32]) throws -> Data {
            var payload = Data(); for value in values { payload.mp4U32(value) }; return try Self.full(type, payload)
        }
        var sampleTable = stsd
        sampleTable.append(try table("stts", [1, sampleCount, UInt32(sampleDelta)]))
        sampleTable.append(try table("stsc", [1, 1, sampleCount, 1]))
        var sampleSizes: [UInt32] = [0, sampleCount]
        var remaining = UInt64(bytes)
        for _ in 0..<sampleCount {
            let count = min(sampleLimit, remaining)
            sampleSizes.append(UInt32(count)); remaining -= count
        }
        sampleTable.append(try table("stsz", sampleSizes))
        sampleTable.append(try table("stco", [1, offset]))
        var mediaInfo = try Self.full("nmhd", Data()); mediaInfo.append(dinf)
        mediaInfo.append(try Self.box("stbl", sampleTable))
        var media = mdhd; media.append(hdlr); media.append(try Self.box("minf", mediaInfo))
        var track = tkhd; track.append(try Self.box("mdia", media))
        return try Self.box("trak", track)
    }
}

private extension Data {
    mutating func mp4U16(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value >> 8)); append(UInt8(truncatingIfNeeded: value)) }
    mutating func mp4U32(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24)); append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8)); append(UInt8(truncatingIfNeeded: value))
    }
    mutating func mp4U64(_ value: UInt64) { mp4U32(UInt32(truncatingIfNeeded: value >> 32)); mp4U32(UInt32(truncatingIfNeeded: value)) }
    mutating func mp4Set32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value >> 24); self[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 8); self[offset + 3] = UInt8(truncatingIfNeeded: value)
    }
    func mp4Read16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= count - 2 else { throw SessionMP4Writer.ExportError.unsupportedMovie("truncated uint16") }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }
    func mp4Read32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= count - 4 else { throw SessionMP4Writer.ExportError.unsupportedMovie("truncated uint32") }
        return (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16) | (UInt32(self[offset + 2]) << 8) | UInt32(self[offset + 3])
    }
    func mp4Read64(_ offset: Int) throws -> UInt64 { (UInt64(try mp4Read32(offset)) << 32) | UInt64(try mp4Read32(offset + 4)) }
}
