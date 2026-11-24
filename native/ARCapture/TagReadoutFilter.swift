import Foundation
import CoreFoundation

/// Optional presentation smoothing. Feed each accepted analysis result exactly once,
/// and keep this output separate from recorded detections and spatial geometry.
struct TagReadoutFilter {
    private struct Key: Hashable {
        let tagID: Int
        let signal: String
    }
    private struct Estimate {
        var value: Double
        var covariance: Double
        let context: [String]
    }
    private var estimates: [Key: Estimate] = [:]
    private var previousTimestamp: Double?
    private var previousSamples: Int?
    private static let sampleOptions = [3, 5, 10, 20, 30]

    mutating func reset() {
        estimates.removeAll()
        previousTimestamp = nil
        previousSamples = nil
    }

    mutating func apply(to detections: [[String: Any]], timestamp: Double,
                        enabled: Bool, samples: Int) -> [[String: Any]] {
        guard enabled, Self.sampleOptions.contains(samples), timestamp.isFinite else {
            reset(); return detections
        }
        if let previousTimestamp, timestamp <= previousTimestamp {
            reset(); return detections
        }
        let elapsed = previousTimestamp.map { timestamp - $0 } ?? 1.0 / 30.0
        if previousSamples != samples || elapsed > 0.4 { estimates.removeAll() }
        previousSamples = samples
        previousTimestamp = timestamp
        let alpha = 2.0 / Double(samples + 1)
        // Random-walk Kalman model, normalized measurement variance R = 1.
        // At 30 Hz, Q/R = alpha²/(1-alpha) produces steady-state gain alpha.
        // "Samples" therefore sets equivalent response strength, not a history window.
        let processVariance = alpha * alpha / (1 - alpha) * elapsed * 30
        let metadata: [String: Any] = ["method": "kalman", "samples": samples,
            "responseConvention": "equivalent samples at 30 Hz"]
        let ids = detections.compactMap { Self.tagID($0["id"]) }
        let counts = Dictionary(ids.map { ($0, 1) }, uniquingKeysWith: +)
        var active = Set<Key>()
        let output = detections.map { detection -> [String: Any] in
            // Ambiguous duplicate IDs must not share and advance the same estimate twice.
            guard let id = Self.tagID(detection["id"]), counts[id] == 1 else { return detection }
            var result = detection
            var debug = detection["debug"] as? [String: Any] ?? [:]
            var changed = false
            if var height = detection["floorHeight"] as? [String: Any],
               Self.isTrue(height["available"]), let raw = Self.number(height["meters"]), raw >= 0 {
                let key = Key(tagID: id, signal: "floorHeight")
                let context = [height["segmentId"] as? String ?? "", height["floorId"] as? String ?? "",
                               height["source"] as? String ?? ""]
                height["rawMeters"] = raw
                height["meters"] = update(key: key, measurement: raw, context: context,
                    alpha: alpha, processVariance: processVariance)
                height["readoutFilter"] = metadata
                result["floorHeight"] = height; debug["floorHeight"] = height
                active.insert(key); changed = true
            }
            if var ranges = detection["cameraRanges"] as? [String: Any] {
                var filteredRange = false
                for (signal, flag, rawKey) in [("lidarRangeMeters", "lidarAvailable", "rawLidarRangeMeters"),
                                                ("tagRangeMeters", "tagAvailable", "rawTagRangeMeters")] {
                    guard Self.isTrue(ranges[flag]), let raw = Self.number(ranges[signal]), raw > 0 else { continue }
                    let key = Key(tagID: id, signal: signal)
                    ranges[rawKey] = raw
                    ranges[signal] = update(key: key, measurement: raw,
                        context: [ranges["segmentId"] as? String ?? ""],
                        alpha: alpha, processVariance: processVariance)
                    active.insert(key); filteredRange = true
                }
                if filteredRange {
                    ranges["rawDistanceDeltaMeters"] = ranges["distanceDeltaMeters"] ?? NSNull()
                    if Self.isTrue(ranges["lidarAvailable"]), Self.isTrue(ranges["tagAvailable"]),
                       let lidar = Self.number(ranges["lidarRangeMeters"]), lidar > 0,
                       let tag = Self.number(ranges["tagRangeMeters"]), tag > 0 {
                        ranges["distanceDeltaMeters"] = abs(lidar - tag)
                    } else { ranges["distanceDeltaMeters"] = NSNull() }
                    ranges["readoutFilter"] = metadata
                    result["cameraRanges"] = ranges; debug["cameraRanges"] = ranges
                    changed = true
                }
            }
            if changed {
                result["readoutFilter"] = metadata; debug["readoutFilter"] = metadata
                result["debug"] = debug
            }
            return result
        }
        // A disappeared tag or unavailable signal starts fresh when it returns.
        estimates = estimates.filter { active.contains($0.key) }
        return output
    }

    private mutating func update(key: Key, measurement: Double, context: [String],
                                 alpha: Double, processVariance: Double) -> Double {
        guard var estimate = estimates[key], estimate.context == context else {
            estimates[key] = Estimate(value: measurement, covariance: alpha, context: context)
            return measurement
        }
        let predictedCovariance = estimate.covariance + processVariance
        let gain = predictedCovariance / (predictedCovariance + 1)
        // Convex form avoids overflow from subtracting large opposite measurements.
        estimate.value = (1 - gain) * estimate.value + gain * measurement
        estimate.covariance = (1 - gain) * predictedCovariance
        estimates[key] = estimate
        return estimate.value
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private static func isTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }
    private static func tagID(_ value: Any?) -> Int? {
        guard let value = number(value), value >= 0, value < Double(Int.max), value.rounded() == value else { return nil }
        return Int(value)
    }
}
