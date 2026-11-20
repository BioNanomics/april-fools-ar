import Foundation

/// A Foundation-only ZIP writer. Stored entries and signed data descriptors allow
/// one bounded-memory read of each file; ZIP64 is deliberately unsupported.
struct SessionZIPWriter {
    struct Result {
        let url: URL
        let bytes: UInt64
    }

    enum ArchiveError: LocalizedError {
        case invalidSource(String)
        case invalidEntry(String)
        case unsupportedSize
        case sourceChanged(String)
        case cannotCreateArchive

        var errorDescription: String? {
            switch self {
            case .invalidSource(let reason): return "Invalid session folder: \(reason)"
            case .invalidEntry(let name): return "Unsupported archive entry: \(name)"
            case .unsupportedSize: return "This session requires ZIP64. Export supports archives below 4 GiB and fewer than 65,535 entries."
            case .sourceChanged(let name): return "Session changed during export: \(name). Finalize the session and try again."
            case .cannotCreateArchive: return "Unable to create the session archive."
            }
        }
    }

    private struct Entry {
        let url: URL
        let name: String
        let directory: Bool
        let expectedSize: UInt64
        let modificationDate: Date
    }

    private struct CentralEntry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
        let time: UInt16
        let date: UInt16
        let directory: Bool
    }

    private static let chunkBytes = 64 * 1024
    private static let zip32Limit = UInt64(UInt32.max)
    private static let flags: UInt16 = 0x0808 // UTF-8 names + data descriptor.

    /// `allowedSessionsRoot` is injected for the standalone validation harness.
    /// Production callers must use Documents/AprilFoolsAR/sessions.
    func archiveSession(folderPath: String, allowedSessionsRoot: URL,
                        destinationDirectory: URL) throws -> Result {
        let source = try validatedSource(folderPath, root: allowedSessionsRoot)
        let entries = try collectEntries(in: source)
        guard entries.count < Int(UInt16.max) else { throw ArchiveError.unsupportedSize }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory,
                                        withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(
            "AprilFoolsAR-\(source.lastPathComponent)-\(UUID().uuidString).zip")
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw ArchiveError.cannotCreateArchive
        }
        var succeeded = false
        defer { if !succeeded { try? fileManager.removeItem(at: destination) } }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var written: UInt64 = 0
        var central: [CentralEntry] = []

        func append(_ data: Data) throws {
            guard UInt64(data.count) < Self.zip32Limit,
                  written < Self.zip32Limit - UInt64(data.count) else {
                throw ArchiveError.unsupportedSize
            }
            try output.write(contentsOf: data)
            written += UInt64(data.count)
        }

        for entry in entries {
            try verifyEntry(entry, inside: source)
            let name = Data(entry.name.utf8)
            guard name.count <= Int(UInt16.max) else { throw ArchiveError.invalidEntry(entry.name) }
            let stamp = Self.dosTimestamp(entry.modificationDate)
            let localOffset = UInt32(written)
            var local = Data()
            local.u32(0x04034b50)
            local.u16(20)
            local.u16(Self.flags)
            local.u16(0) // STORE; no compression.
            local.u16(stamp.time)
            local.u16(stamp.date)
            local.u32(0) // CRC and sizes follow the entry data.
            local.u32(0)
            local.u32(0)
            local.u16(UInt16(name.count))
            local.u16(0)
            local.append(name)
            try append(local)

            var crc = CRC32()
            var size: UInt64 = 0
            if !entry.directory {
                let input = try FileHandle(forReadingFrom: entry.url)
                do {
                    while let chunk = try input.read(upToCount: Self.chunkBytes), !chunk.isEmpty {
                        guard size < Self.zip32Limit - UInt64(chunk.count) else {
                            throw ArchiveError.unsupportedSize
                        }
                        size += UInt64(chunk.count)
                        crc.update(chunk)
                        try append(chunk)
                    }
                    try input.close()
                } catch {
                    try? input.close()
                    throw error
                }
                guard size == entry.expectedSize else { throw ArchiveError.sourceChanged(entry.name) }
                try verifyEntry(entry, inside: source)
            }

            var descriptor = Data()
            descriptor.u32(0x08074b50)
            descriptor.u32(crc.value)
            descriptor.u32(UInt32(size))
            descriptor.u32(UInt32(size))
            try append(descriptor)
            central.append(CentralEntry(name: name, crc: crc.value, size: UInt32(size),
                                        offset: localOffset, time: stamp.time, date: stamp.date,
                                        directory: entry.directory))
        }

        let centralOffset = written
        for entry in central {
            var record = Data()
            record.u32(0x02014b50)
            record.u16(0x0314) // ZIP 2.0, Unix attributes.
            record.u16(20)
            record.u16(Self.flags)
            record.u16(0)
            record.u16(entry.time)
            record.u16(entry.date)
            record.u32(entry.crc)
            record.u32(entry.size)
            record.u32(entry.size)
            record.u16(UInt16(entry.name.count))
            record.u16(0) // Extra.
            record.u16(0) // Comment.
            record.u16(0) // Disk.
            record.u16(0) // Internal attributes.
            record.u32(entry.directory ? (UInt32(0o040755) << 16) | 0x10 : UInt32(0o100644) << 16)
            record.u32(entry.offset)
            record.append(entry.name)
            try append(record)
        }
        let centralSize = written - centralOffset
        var end = Data()
        end.u32(0x06054b50)
        end.u16(0)
        end.u16(0)
        end.u16(UInt16(central.count))
        end.u16(UInt16(central.count))
        end.u32(UInt32(centralSize))
        end.u32(UInt32(centralOffset))
        end.u16(0)
        try append(end)
        try output.synchronize()
        try output.close()
        succeeded = true
        return Result(url: destination, bytes: written)
    }

    private func validatedSource(_ folderPath: String, root: URL) throws -> URL {
        let decoded = folderPath.removingPercentEncoding ?? folderPath
        guard !decoded.contains("\0"), !decoded.split(separator: "/").contains("..") else {
            throw ArchiveError.invalidSource("path traversal is not allowed")
        }
        let supplied: URL
        if folderPath.hasPrefix("file:") {
            guard let url = URL(string: folderPath), url.isFileURL,
                  url.host == nil || url.host == "" || url.host == "localhost" else {
                throw ArchiveError.invalidSource("expected a local file URL")
            }
            supplied = url
        } else {
            guard folderPath.hasPrefix("/") else {
                throw ArchiveError.invalidSource("expected an absolute path")
            }
            supplied = URL(fileURLWithPath: folderPath, isDirectory: true)
        }
        let source = supplied.standardizedFileURL
        let canonicalRoot = try canonicalURL(root)
        let canonicalSource = try canonicalURL(source)
        guard UUID(uuidString: source.lastPathComponent) != nil,
              try canonicalURL(source.deletingLastPathComponent()).path == canonicalRoot.path,
              canonicalSource.deletingLastPathComponent().path == canonicalRoot.path else {
            throw ArchiveError.invalidSource("select one UUID session directly inside the sessions folder")
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory else {
            throw ArchiveError.invalidSource("the session must be a directory, not a symbolic link")
        }
        return canonicalSource
    }

    private func collectEntries(in source: URL) throws -> [Entry] {
        let fileManager = FileManager.default
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(at: source,
            includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in
                enumerationError = error
                return false
            }) else { throw ArchiveError.invalidSource("unable to read the session") }
        var entries: [Entry] = []
        let prefix = source.path + "/"
        for case let url as URL in enumerator {
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            let type = attrs[.type] as? FileAttributeType
            if type == .typeSymbolicLink {
                // DirectoryEnumerator does not traverse symbolic links. Calling
                // skipDescendants() for a link can skip its containing directory.
                continue
            }
            guard type == .typeDirectory || type == .typeRegular,
                  url.path.hasPrefix(prefix) else { throw ArchiveError.invalidEntry(url.lastPathComponent) }
            var name = String(url.path.dropFirst(prefix.count))
            guard !name.isEmpty, !name.contains("\\"), !name.contains(":"), !name.contains("\0"),
                  !name.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
                throw ArchiveError.invalidEntry(name)
            }
            let isDirectory = type == .typeDirectory
            if isDirectory { name += "/" }
            let size = isDirectory ? 0 : (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            guard size < Self.zip32Limit else { throw ArchiveError.unsupportedSize }
            entries.append(Entry(url: url, name: name, directory: isDirectory,
                                 expectedSize: size,
                                 modificationDate: attrs[.modificationDate] as? Date ?? Date()))
            guard entries.count < Int(UInt16.max) else { throw ArchiveError.unsupportedSize }
        }
        if let error = enumerationError { throw error }
        return entries.sorted { $0.name < $1.name }
    }

    private func verifyEntry(_ entry: Entry, inside source: URL) throws {
        let canonical = try canonicalURL(entry.url)
        guard canonical.path == entry.url.path,
              canonical.path.hasPrefix(source.path + "/") else {
            throw ArchiveError.sourceChanged(entry.name)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: entry.url.path)
        let expectedType: FileAttributeType = entry.directory ? .typeDirectory : .typeRegular
        guard attrs[.type] as? FileAttributeType == expectedType,
              entry.directory || (attrs[.size] as? NSNumber)?.uint64Value == entry.expectedSize,
              entry.directory || (attrs[.modificationDate] as? Date) == entry.modificationDate else {
            throw ArchiveError.sourceChanged(entry.name)
        }
    }

    private func canonicalURL(_ url: URL) throws -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        // Foundation may retain /var while directory enumeration emits /private/var.
        // canonicalPath normalizes that filesystem alias after resolving real links.
        let values = try resolved.resourceValues(forKeys: [.canonicalPathKey])
        return URL(fileURLWithPath: values.canonicalPath ?? resolved.path)
    }

    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(2107, max(1980, parts.year ?? 1980))
        let month = min(12, max(1, parts.month ?? 1))
        let day = min(31, max(1, parts.day ?? 1))
        let hour = min(23, max(0, parts.hour ?? 0))
        let minute = min(59, max(0, parts.minute ?? 0))
        let second = min(59, max(0, parts.second ?? 0))
        return (UInt16((hour << 11) | (minute << 5) | (second / 2)),
                UInt16(((year - 1980) << 9) | (month << 5) | day))
    }
}

private extension Data {
    mutating func u16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func u32(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

private struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1 }
        return value
    }
    private var state: UInt32 = 0xffffffff
    mutating func update(_ data: Data) {
        for byte in data { state = Self.table[Int((state ^ UInt32(byte)) & 0xff)] ^ (state >> 8) }
    }
    var value: UInt32 { state ^ 0xffffffff }
}
