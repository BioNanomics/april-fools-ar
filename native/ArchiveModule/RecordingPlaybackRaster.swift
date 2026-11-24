import Foundation
import CoreFoundation
import CryptoKit
import Darwin
import UIKit

/// A held, recorded sensor raster. It is not reprojected into a newer camera pose.
struct RecordingPlaybackRasterSample: Equatable {
    let id: String
    let imageSize: CGSize
    let time: Double
    let segment: String
    let width: Int
    let height: Int
    let depthFile: RecordingPlaybackRasterFile?
    let confidenceFile: RecordingPlaybackRasterFile?
}

struct RecordingPlaybackRasterFile: Equatable {
    let path: String
    let bytes: Int
    let sha256: String
}

/// Only descriptors live in the timeline; raster bytes are loaded on demand.
struct RecordingPlaybackRasterIndex {
    static let maximumPixels = 1_048_576
    let folderURL: URL?
    let samples: [RecordingPlaybackRasterSample]
    private let bySegment: [String: [RecordingPlaybackRasterSample]]

    init(manifest: [String: Any], frames: [[String: Any]], events: [[String: Any]],
         origin: Double, folderURL: URL?) {
        self.folderURL = folderURL
        var inventory = [String: RecordingPlaybackRasterFile](), duplicatePaths = Set<String>(), seenPaths = Set<String>()
        for row in manifest["fileInventory"] as? [[String: Any]] ?? [] {
            guard let path = row["path"] as? String else { continue }
            if !seenPaths.insert(path).inserted { duplicatePaths.insert(path) }
            guard Self.components(path) != nil,
                  let bytes = Self.number(row["bytes"]), bytes.rounded() == bytes,
                  bytes >= 0, bytes <= Double(Self.maximumPixels * 4),
                  let sha = row["sha256"] as? String, sha.utf8.count == 64,
                  sha.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { continue }
            inventory[path] = .init(path: path, bytes: Int(bytes), sha256: sha)
        }
        for path in duplicatePaths { inventory.removeValue(forKey: path) }

        // A measurement/bookmark can save a sample before the normal 5 Hz disk
        // pass. Reused paths then omit dimensions; merge that frame's records.
        let fields = ["timestamp", "imageWidth", "imageHeight", "depthWidth", "depthHeight",
                      "depthPath", "confidencePath", "depthEncoding", "confidenceEncoding"]
        var merged = [String: [String: Any]](), conflicts = Set<String>()
        for row in frames + events {
            guard let segment = row["segmentId"] as? String, !segment.isEmpty,
                  let frame = row["frameId"] as? String, !frame.isEmpty else { continue }
            let key = "\(segment.utf8.count):\(segment)\(frame)"
            var value = merged[key] ?? ["segmentId": segment, "frameId": frame]
            for field in fields {
                guard let next = row[field] else { continue }
                if let previous = value[field] {
                    if (previous as? NSObject)?.isEqual(next) != true { conflicts.insert(key) }
                } else { value[field] = next }
            }
            merged[key] = value
        }
        var samples = [RecordingPlaybackRasterSample]()
        for (key, row) in merged where !conflicts.contains(key) {
            guard let timestamp = Self.number(row["timestamp"]), timestamp >= origin,
                  let widthValue = Self.number(row["depthWidth"]), let heightValue = Self.number(row["depthHeight"]),
                  widthValue.rounded() == widthValue, heightValue.rounded() == heightValue,
                  widthValue > 0, heightValue > 0, widthValue <= Double(Self.maximumPixels),
                  heightValue <= Double(Self.maximumPixels), widthValue * heightValue <= Double(Self.maximumPixels),
                  let imageWidth = Self.number(row["imageWidth"]), let imageHeight = Self.number(row["imageHeight"]),
                  imageWidth > 0, imageHeight > 0, imageWidth <= 65535, imageHeight <= 65535,
                  abs((widthValue / heightValue) / (imageWidth / imageHeight) - 1) < 0.001,
                  let segment = row["segmentId"] as? String else { continue }
            let width = Int(widthValue), height = Int(heightValue)
            func file(_ pathKey: String, _ encodingKey: String, _ encoding: String, bytesPerPixel: Int) -> RecordingPlaybackRasterFile? {
                guard row[encodingKey] == nil || row[encodingKey] as? String == encoding,
                      let path = row[pathKey] as? String, let file = inventory[path],
                      file.bytes == width * height * bytesPerPixel else { return nil }
                return file
            }
            let depth = file("depthPath", "depthEncoding", "float32-little-endian-packed-camera-plane-Z-meters", bytesPerPixel: 4)
            let confidence = file("confidencePath", "confidenceEncoding", "uint8-packed-ARConfidenceLevel-0-low-1-medium-2-high", bytesPerPixel: 1)
            guard depth != nil || confidence != nil else { continue }
            samples.append(.init(id: key, imageSize: CGSize(width: imageWidth, height: imageHeight),
                                 time: timestamp-origin, segment: segment, width: width, height: height,
                                 depthFile: depth, confidenceFile: confidence))
        }
        samples.sort { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        self.samples = samples
        self.bySegment = Dictionary(grouping: samples, by: \.segment)
    }

    func sample(at seconds: Double, segment: String, imageSize: CGSize) -> RecordingPlaybackRasterSample? {
        guard let candidates = bySegment[segment] else { return nil }
        var lower = 0, upper = candidates.count
        while lower < upper {
            let middle = lower + (upper-lower)/2
            if candidates[middle].time <= seconds+1e-7 { lower = middle+1 } else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let sample = candidates[lower-1]
        guard seconds-sample.time >= -1e-7, seconds-sample.time <= 0.4+1e-7,
              abs((sample.imageSize.width/sample.imageSize.height) / (imageSize.width/imageSize.height)-1) < 0.001 else { return nil }
        return sample
    }

    static func components(_ path: String) -> [String]? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.count <= 16, parts.first == "depth",
              !path.contains("\\"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return parts
    }
    private static func number(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
}

extension RecordingPlaybackTimeline {
    /// Call off the main thread. No raster cache or UI work is retained here.
    func rasterImage(for sample: RecordingPlaybackRasterSample, mode: String) throws -> UIImage {
        try autoreleasepool {
            guard rasterIndex.samples.contains(sample), let folder = rasterIndex.folderURL,
                  folder.isFileURL, ["depth", "confidence"].contains(mode),
                  let file = mode == "depth" ? sample.depthFile : sample.confidenceFile else {
                throw TimelineError.invalid("this frame has no saved \(mode) sample")
            }
            let data = try Self.readRaster(file, folder: folder)
            return try RecordingPlaybackRaster.image(data: data, width: sample.width, height: sample.height, mode: mode)
        }
    }

    private static func readRaster(_ file: RecordingPlaybackRasterFile, folder: URL) throws -> Data {
        guard let parts = RecordingPlaybackRasterIndex.components(file.path) else { throw TimelineError.invalid("invalid sensor sample path") }
        var directory = Darwin.open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw TimelineError.invalid("the capture folder cannot be opened") }
        defer { Darwin.close(directory) }
        for part in parts.dropLast() {
            let next = openat(directory, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw TimelineError.invalid("the sensor sample directory cannot be opened") }
            Darwin.close(directory); directory = next
        }
        let descriptor = openat(directory, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw TimelineError.invalid("the sensor sample cannot be opened") }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size == file.bytes, file.bytes > 0,
              file.bytes <= RecordingPlaybackRasterIndex.maximumPixels * 4 else {
            throw TimelineError.invalid("the sensor sample has an invalid size")
        }
        var data = Data(count: file.bytes)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), min(65536, buffer.count-offset))
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw TimelineError.invalid("the sensor sample is incomplete") }
                offset += count
            }
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size, before.st_ino == after.st_ino,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw TimelineError.invalid("the sensor sample does not match the saved capture")
        }
        return data
    }
}

enum RecordingPlaybackRaster {
    static func image(data: Data, width: Int, height: Int, mode: String) throws -> UIImage {
        guard width > 0, height > 0, width <= RecordingPlaybackRasterIndex.maximumPixels,
              height <= RecordingPlaybackRasterIndex.maximumPixels,
              width * height <= RecordingPlaybackRasterIndex.maximumPixels,
              ["depth", "confidence"].contains(mode), data.count == width * height * (mode == "depth" ? 4 : 1) else {
            throw RecordingPlaybackTimeline.TimelineError.invalid("the sensor raster has invalid dimensions")
        }
        var pixels = [UInt8](repeating: 0, count: width*height*4)
        data.withUnsafeBytes { input in
            let bytes = input.bindMemory(to: UInt8.self)
            for index in 0..<(width*height) {
                let output = index*4
                if mode == "confidence" {
                    let value = bytes[index]
                    if value <= 2 {
                        pixels[output] = value == 2 ? 25 : 240
                        pixels[output+1] = value == 0 ? 30 : 220
                        pixels[output+2] = 40
                    }
                } else {
                    let offset = index*4
                    let bits = UInt32(bytes[offset]) | UInt32(bytes[offset+1]) << 8 |
                        UInt32(bytes[offset+2]) << 16 | UInt32(bytes[offset+3]) << 24
                    let z = Float(bitPattern: bits)
                    if z.isFinite && z > 0 {
                        let t = max(0, min(1, z/6))
                        pixels[output] = UInt8(255*(1-t))
                        pixels[output+1] = UInt8(200*(1-abs(t*2-1)))
                        pixels[output+2] = UInt8(255*t)
                    }
                }
                pixels[output+3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw RecordingPlaybackTimeline.TimelineError.invalid("the sensor raster cannot be rendered")
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}
