import Foundation
import ARKit
import AVFoundation
import CoreImage
import UIKit
import CryptoKit
import Darwin

/// Disk ownership stays on one queue; at most three camera frames are retained for disk work.
final class CaptureRecorder {
    let id = UUID().uuidString
    let name: String
    let createdAt = Date()
    let folder: URL
    private let initialDebugSettings: TagDebugSettings
    private let initialTagSizeEvidence: [String: Any]?
    private let initialApplication: [String: Any]
    private let queue = DispatchQueue(label: "AprilFoolsAR.capture.disk", qos: .utility)
    private let slots = DispatchSemaphore(value: 3)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var framesFile: FileHandle!
    private var eventsFile: FileHandle!
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstTimestamp: TimeInterval?
    private var lastVideoTimestamp = -Double.infinity
    private var lastSampleTimestamp = -Double.infinity
    private var lastTimestamp: TimeInterval?
    private var framesWritten = 0
    private var depthFrames = 0
    private var videoFrames = 0
    private var droppedVideoFrames = 0
    private var bytesWritten: Int64 = 0
    private var errors = [String]()
    private var sampledIDs = Set<String>()
    private var tagAnalyzedFrames = 0
    private var tagPositiveFrames = 0
    private var tagErrors = 0
    // Called only from captureQueue; disk work remains on queue.
    private var lastTagSnapshotRequestedTimestamp = -Double.infinity
    private var recentDropCount = 0
    private let expirationLock = NSLock()
    private var backgroundExpired = false
    private(set) var finalized = false
    var onProgress: (([String: Any]) -> Void)?

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AprilFoolsAR/sessions", isDirectory: true)
    }

    init(name: String, debugSettings: TagDebugSettings = .load(), application: [String: Any] = AppBuildInfo.application) throws {
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        initialDebugSettings = debugSettings
        initialTagSizeEvidence = debugSettings.matchingTagSizeEvidence()
        initialApplication = application
        folder = Self.root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("frames"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("depth"), withIntermediateDirectories: true)
        let framesURL = folder.appendingPathComponent("frames.jsonl")
        let eventsURL = folder.appendingPathComponent("events.jsonl")
        FileManager.default.createFile(atPath: framesURL.path, contents: nil)
        FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        framesFile = try FileHandle(forWritingTo: framesURL)
        eventsFile = try FileHandle(forWritingTo: eventsURL)
        try writeManifest(finalized: false)
        writeEvent(["type": "recordingStarted", "wallTime": Self.iso(createdAt), "application": initialApplication])
    }

    func append(frame: ARFrame, metadata: [String: Any]) -> Bool {
        guard slots.wait(timeout: .now()) == .success else { return false }
        queue.async { [self] in
            defer { slots.signal() }
            autoreleasepool {
                do {
                    var record = metadata
                    if firstTimestamp == nil { firstTimestamp = frame.timestamp }
                    lastTimestamp = frame.timestamp
                    let pts = frame.timestamp - (firstTimestamp ?? frame.timestamp)
                    record["videoPTSSeconds"] = pts
                    record["videoAppended"] = false
                    if frame.timestamp - lastVideoTimestamp >= (1.0 / 30.0 - 0.002) {
                        lastVideoTimestamp = frame.timestamp
                        try ensureVideo(buffer: frame.capturedImage)
                        if let input = videoInput, let adaptor = adaptor, input.isReadyForMoreMediaData {
                            let ok = adaptor.append(frame.capturedImage, withPresentationTime: CMTime(seconds: pts, preferredTimescale: 600_000))
                            record["videoAppended"] = ok
                            if ok { videoFrames += 1 }
                            else { droppedVideoFrames += 1; recordError(assetWriter?.error?.localizedDescription ?? "Video append failed") }
                        } else { droppedVideoFrames += 1 }
                    }
                    if frame.timestamp - lastSampleTimestamp >= 0.2 - 0.002 {
                        lastSampleTimestamp = frame.timestamp
                        let paths = try saveSamples(frame: frame, frameID: metadata["frameId"] as? String ?? UUID().uuidString)
                        for (key, value) in paths { record[key] = value }
                    }
                    try appendJSON(record, to: framesFile)
                    framesWritten += 1
                    if framesWritten % 30 == 0 { publishProgress() }
                } catch { recordError(error.localizedDescription); publishProgress() }
            }
        }
        return true
    }

    /// Events are small and never dropped. A bookmark retains one frame only if the bounded pool permits.
    func event(_ event: [String: Any], frame: ARFrame? = nil, frameID: String? = nil) {
        let captureFrame = frame != nil && slots.wait(timeout: .now()) == .success
        let retainedFrame = captureFrame ? frame : nil
        let hadFrame = frame != nil
        queue.async { [self] in
            defer { if captureFrame { slots.signal() } }
            autoreleasepool {
                var record = event
                if captureFrame, let frame = retainedFrame, let frameID {
                    do {
                        let paths = try saveSamples(frame: frame, frameID: frameID)
                        for (key, value) in paths { record[key] = value }
                    } catch { record["captureError"] = error.localizedDescription; recordError(error.localizedDescription) }
                } else if hadFrame { record["frameCaptureSkipped"] = "bounded writer queue busy" }
                do { try appendJSON(record, to: eventsFile) } catch { recordError(error.localizedDescription) }
            }
        }
    }

    /// Analysis metadata is recorded for empty results too. Positive-result image retention shares the bounded writer pool.
    func aprilTagEvent(_ event: [String: Any], pixelBuffer: CVPixelBuffer?, frameID: String) {
        let timestamp = (event["timestamp"] as? NSNumber)?.doubleValue ?? -Double.infinity
        let snapshotDue = pixelBuffer != nil && timestamp - lastTagSnapshotRequestedTimestamp >= 0.2
        let captureImage = snapshotDue && slots.wait(timeout: .now()) == .success
        if captureImage { lastTagSnapshotRequestedTimestamp = timestamp }
        let retainedBuffer = captureImage ? pixelBuffer : nil
        let hadImage = pixelBuffer != nil
        queue.async { [self] in
            defer { if captureImage { slots.signal() } }
            autoreleasepool {
                var record = event
                if event["analysisSucceeded"] as? Bool == true { tagAnalyzedFrames += 1 } else { tagErrors += 1 }
                if let detections = event["detections"] as? [[String: Any]], !detections.isEmpty { tagPositiveFrames += 1 }
                if let buffer = retainedBuffer {
                    do { record["rgbImagePath"] = try saveRGBImage(buffer, frameID: frameID) }
                    catch { record["captureError"] = error.localizedDescription; recordError(error.localizedDescription) }
                } else if hadImage {
                    record["frameCaptureSkipped"] = snapshotDue ? "bounded writer queue busy" : "positive-tag JPEG snapshot limited to 5 Hz; numeric result retained"
                }
                do { try appendJSON(record, to: eventsFile) } catch { recordError(error.localizedDescription) }
            }
        }
    }

    func backgroundExecutionExpired() {
        expirationLock.lock(); backgroundExpired = true; expirationLock.unlock()
    }

    private var wasBackgroundExpired: Bool {
        expirationLock.lock(); defer { expirationLock.unlock() }; return backgroundExpired
    }

    func finish(droppedFrames: Int, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        queue.async { [self] in
            recentDropCount = droppedFrames
            writeEvent(["type": "recordingStopped", "wallTime": Self.iso(Date()), "droppedFrames": droppedFrames])
            let finishFiles = { [self] in
                queue.async { [self] in
                    do {
                        try framesFile.synchronize(); try eventsFile.synchronize()
                        try framesFile.close(); try eventsFile.close()
                        if let error = assetWriter?.error { throw error }
                        if wasBackgroundExpired { throw CaptureError.message("Background finalization expired; session remains unfinalized.") }
                        try writeManifest(finalized: true)
                        finalized = true
                        var result = sessionRecord()
                        result["errors"] = errors
                        completion(.success(result))
                    } catch {
                        finalized = false
                        recordError(error.localizedDescription)
                        try? writeManifest(finalized: false)
                        completion(.failure(error))
                    }
                }
            }
            if let writer = assetWriter, writer.status == .writing {
                videoInput?.markAsFinished()
                writer.finishWriting(completionHandler: finishFiles)
            } else { finishFiles() }
        }
    }

    private func ensureVideo(buffer: CVPixelBuffer) throws {
        guard assetWriter == nil else { return }
        let writer = try AVAssetWriter(outputURL: folder.appendingPathComponent("rgb.mp4"), fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: CVPixelBufferGetWidth(buffer), AVVideoHeightKey: CVPixelBufferGetHeight(buffer),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000, AVVideoExpectedSourceFrameRateKey: 30, AVVideoMaxKeyFrameIntervalKey: 30]
        ])
        input.expectsMediaDataInRealTime = true
        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw CaptureError.message("Video writer cannot accept camera format") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CaptureError.message("Video writer failed to start") }
        writer.startSession(atSourceTime: .zero)
        assetWriter = writer; videoInput = input; adaptor = pixelAdaptor
    }

    private func saveSamples(frame: ARFrame, frameID: String) throws -> [String: Any] {
        let rgbPath = "frames/\(frameID).jpg"
        let depthPath = "depth/\(frameID).f32"
        let confidencePath = "depth/\(frameID).confidence.u8"
        if sampledIDs.contains(frameID) {
            var paths: [String: Any] = ["rgbImagePath": rgbPath]
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(depthPath).path) { paths["depthPath"] = depthPath }
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(confidencePath).path) { paths["confidencePath"] = confidencePath }
            return paths
        }
        var paths: [String: Any] = [:]
        paths["rgbImagePath"] = try saveRGBImage(frame.capturedImage, frameID: frameID)
        if let depth = frame.sceneDepth {
            let data = Self.packedData(depth.depthMap, bytesPerPixel: 4)
            try data.write(to: folder.appendingPathComponent(depthPath), options: .atomic)
            bytesWritten += Int64(data.count); paths["depthPath"] = depthPath
            paths["depthSource"] = "sceneDepth"
            paths["depthWidth"] = CVPixelBufferGetWidth(depth.depthMap)
            paths["depthHeight"] = CVPixelBufferGetHeight(depth.depthMap)
            paths["depthSourceBytesPerRow"] = CVPixelBufferGetBytesPerRow(depth.depthMap)
            paths["depthEncoding"] = "float32-little-endian-packed-camera-plane-Z-meters"
            if let confidence = depth.confidenceMap {
                let bytes = Self.packedData(confidence, bytesPerPixel: 1)
                try bytes.write(to: folder.appendingPathComponent(confidencePath), options: .atomic)
                bytesWritten += Int64(bytes.count); paths["confidencePath"] = confidencePath
                paths["confidenceEncoding"] = "uint8-packed-ARConfidenceLevel-0-low-1-medium-2-high"
            }
            depthFrames += 1
        }
        sampledIDs.insert(frameID)
        return paths
    }

    private func saveRGBImage(_ buffer: CVPixelBuffer, frameID: String) throws -> String {
        let path = "frames/\(frameID).jpg", url = folder.appendingPathComponent("frames/\(frameID).jpg")
        if FileManager.default.fileExists(atPath: url.path) { return path }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let jpeg = ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.94]) else { throw CaptureError.message("Could not encode camera image") }
        try jpeg.write(to: url, options: .atomic); bytesWritten += Int64(jpeg.count)
        return path
    }

    static func packedData(_ buffer: CVPixelBuffer, bytesPerPixel: Int) -> Data {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return Data() }
        let rowBytes = CVPixelBufferGetWidth(buffer) * bytesPerPixel
        let sourceStride = CVPixelBufferGetBytesPerRow(buffer)
        var data = Data(capacity: rowBytes * CVPixelBufferGetHeight(buffer))
        for row in 0..<CVPixelBufferGetHeight(buffer) { data.append(base.advanced(by: row * sourceStride).assumingMemoryBound(to: UInt8.self), count: rowBytes) }
        return data
    }

    private func appendJSON(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10); try handle.write(contentsOf: data); bytesWritten += Int64(data.count)
    }
    private func writeEvent(_ object: [String: Any]) {
        do { try appendJSON(object, to: eventsFile) } catch { recordError(error.localizedDescription) }
    }
    private func recordError(_ text: String) { if errors.last != text && errors.count < 100 { errors.append(text) } }
    private func publishProgress() {
        let videoBytes = (try? folder.appendingPathComponent("rgb.mp4").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        onProgress?(["framesWritten": framesWritten, "depthFrames": depthFrames, "videoFrames": videoFrames,
                     "videoDroppedFrames": droppedVideoFrames, "bytesWritten": bytesWritten + Int64(videoBytes),
                     "lastError": errors.last as Any? ?? NSNull()])
    }
    private func writeManifest(finalized: Bool) throws {
        var manifest = sessionRecord()
        manifest["schemaVersion"] = 1
        manifest["application"] = initialApplication
        manifest["calculationCore"] = SpatialCoreInfo.dictionary(application: initialApplication)
        manifest["device"] = ["model": UIDevice.current.model, "hardwareIdentifier": Self.hardwareIdentifier(), "systemVersion": UIDevice.current.systemVersion]
        manifest["finalized"] = finalized
        manifest["clock"] = "ARFrame.timestamp: seconds since system boot; video PTS relative to first recorded AR frame"
        manifest["firstARFrameTimestamp"] = firstTimestamp as Any? ?? NSNull()
        manifest["coordinateConvention"] = "ARKit right-handed, gravity aligned +Y up, camera looks along -Z; camera transforms column-major camera-to-world; depth is camera-plane Z in meters"
        manifest["captureDefaults"] = ["videoFPS": 30, "depthAndJPEGHz": 5, "maxRetainedWriterFrames": 3, "jpegQuality": 0.94, "videoBitrate": 10_000_000]
        manifest["aprilTagConfiguration"] = ["enabled": true, "family": "tag36h11", "implementation": "AprilRobotics/apriltag via AFTagDetector", "upstreamRevision": AFTagDetector.upstreamRevision(), "quadDecimate": 2, "threads": 2, "targetAnalysisHz": 30, "analysisScheduling": "one in flight; no artificial throttle; actual throughput recorded", "maxInFlight": 1, "poseEstimation": true, "coordinates": "full-resolution capturedImage sensor pixels; camera optical XYZ", "overlayMaximumAgeSeconds": 0.4, "positiveDetectionJPEGMaxHz": 5, "debugSettingsAtStart": initialDebugSettings.dictionary]
        manifest["aprilTagCounts"] = ["analyzedFrames": tagAnalyzedFrames, "positiveFrames": tagPositiveFrames, "errors": tagErrors]
        manifest["tagSizeEvidenceAtStart"] = initialTagSizeEvidence as Any? ?? NSNull()
        manifest["counts"] = ["metadataFrames": framesWritten, "depthFrames": depthFrames, "videoFrames": videoFrames, "writerDroppedFrames": recentDropCount, "videoDroppedFrames": droppedVideoFrames]
        manifest["files"] = ["frames": "frames.jsonl", "events": "events.jsonl", "video": "rgb.mp4", "images": "frames/", "depth": "depth/"]
        manifest["videoContent"] = ["source": "ARFrame.capturedImage", "codec": "h264", "overlaysBurnedIn": false, "audioRecorded": false]
        manifest["evidence"] = "Live capture; measurement accuracy has not been independently validated. AR world poses are not surveyed field truth."
        manifest["errors"] = errors
        manifest["backgroundFinalizationExpired"] = wasBackgroundExpired
        if finalized {
            let inventory = try payloadInventory()
            if wasBackgroundExpired { throw CaptureError.message("Background finalization expired during checksumming; session remains unfinalized.") }
            manifest["fileInventory"] = inventory
            manifest["payloadSizeBytes"] = inventory.reduce(Int64(0)) { $0 + ($1["bytes"] as? Int64 ?? 0) }
            manifest["checksumConvention"] = "SHA-256 per payload file; manifest.json excluded to avoid self-reference"
        }
        manifest.removeValue(forKey: "sizeBytes")
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }
    private func sessionRecord() -> [String: Any] {
        ["id": id, "sessionId": id, "name": name, "createdAt": Self.iso(createdAt), "durationSeconds": max(0, (lastTimestamp ?? firstTimestamp ?? 0) - (firstTimestamp ?? 0)), "sizeBytes": Self.directorySize(folder), "folderPath": folder.path, "manifestPath": folder.appendingPathComponent("manifest.json").path, "finalized": finalized]
    }
    static func directorySize(_ folder: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    private func payloadInventory() throws -> [[String: Any]] {
        let canonicalRoot = folder.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = canonicalRoot.pathComponents
        guard let files = FileManager.default.enumerator(at: canonicalRoot, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
        var result = [[String: Any]]()
        for case let url as URL in files {
            if wasBackgroundExpired { throw CaptureError.message("Background finalization expired during checksumming.") }
            guard url.lastPathComponent != "manifest.json" else { continue }
            let canonicalFile = url.standardizedFileURL.resolvingSymlinksInPath()
            let components = canonicalFile.pathComponents
            guard components.count > rootComponents.count, Array(components.prefix(rootComponents.count)) == rootComponents else { throw CaptureError.message("Payload path escaped the session folder.") }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let handle = try FileHandle(forReadingFrom: url)
            var hash = SHA256()
            do {
                while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                    if wasBackgroundExpired { throw CaptureError.message("Background finalization expired during checksumming.") }
                    hash.update(data: chunk)
                }
                try handle.close()
            } catch { try? handle.close(); throw error }
            result.append(["path": components.dropFirst(rootComponents.count).joined(separator: "/"), "bytes": Int64(values.fileSize ?? 0), "sha256": hash.finalize().map { String(format: "%02x", $0) }.joined()])
        }
        return result.sorted { ($0["path"] as? String ?? "") < ($1["path"] as? String ?? "") }
    }
    private static func hardwareIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
