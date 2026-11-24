import Foundation

enum RecordingMode: String {
    case video, facts
}

/// Capture budgets match the exporter. Package size is a conservative estimate
/// because its readable YAML and TAR padding are produced only on save.
struct RecordingCapacity {
    static let metadataBytes: Int64 = 32 * 1024 * 1024
    static let summaryBytes: Int64 = 32 * 1024 * 1024
    static let yamlBytes: Int64 = 64 * 1024 * 1024
    static let packageBytes: Int64 = Int64(UInt32.max) - 1
    static let records: Int64 = 100_000
    static let entries: Int64 = 65_534
    static let automaticSaveFraction = 0.95

    struct Resource {
        let name: String
        let used: Int64
        let limit: Int64
        var unit = "bytes"
        var estimated = false
        var fraction: Double { Double(max(0, used)) / Double(max(1, limit)) }
    }

    static func snapshot(mode: RecordingMode, frameBytes: Int64 = 0, eventBytes: Int64 = 0,
                         frameYAMLBytes: Int64 = 0, eventYAMLBytes: Int64 = 0,
                         frameRecords: Int64 = 0, eventRecords: Int64 = 0,
                         sourceBytes: Int64 = 0, fileEntries: Int64 = 0,
                         summaryBytes: Int64 = 0, availableStorage: Int64? = nil) -> [String: Any] {
        var resources: [Resource]
        if mode == .facts {
            resources = [Resource(name: "Tag facts summary", used: summaryBytes, limit: Self.summaryBytes)]
        } else {
            // Originals remain in the TAR. Log YAML sizes are counted with the
            // exporter's serializer; padding and inventory metadata are estimated.
            let package = sourceBytes + frameYAMLBytes + eventYAMLBytes + fileEntries * 1024 + 2 * 1024 * 1024
            resources = [
                Resource(name: "Frame metadata", used: frameBytes, limit: metadataBytes),
                Resource(name: "Event metadata", used: eventBytes, limit: metadataBytes),
                Resource(name: "Frame YAML metadata", used: frameYAMLBytes, limit: yamlBytes),
                Resource(name: "Event YAML metadata", used: eventYAMLBytes, limit: yamlBytes),
                Resource(name: "Frame records", used: frameRecords, limit: records, unit: "records"),
                Resource(name: "Event records", used: eventRecords, limit: records, unit: "records"),
                Resource(name: "Capture files", used: fileEntries, limit: entries, unit: "entries"),
                Resource(name: "Packaged recording", used: package, limit: packageBytes, estimated: true)
            ]
            if let availableStorage {
                resources.append(Resource(name: "Storage for saving", used: package,
                    limit: max(1, availableStorage - 250_000_000), estimated: true))
            }
        }
        let limiting = resources.max { $0.fraction < $1.fraction }!
        return ["usedBytes": limiting.used, "limitBytes": limiting.limit,
                "remainingBytes": max(0, limiting.limit - limiting.used),
                "fractionUsed": min(1, limiting.fraction), "limitingResource": limiting.name,
                "unit": limiting.unit, "estimated": limiting.estimated,
                "automaticSaveFraction": automaticSaveFraction,
                "shouldStop": limiting.fraction >= automaticSaveFraction]
    }
}
