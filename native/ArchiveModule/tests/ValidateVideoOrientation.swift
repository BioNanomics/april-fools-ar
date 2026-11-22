import Foundation
import AVFoundation
import CoreVideo

/// macOS AVAssetWriter integration coverage; no camera, AR session or device.
/// Usage: ValidateVideoOrientation NEW_OUTPUT.mp4
@main
enum ValidateVideoOrientation {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw failure("Expected NEW_OUTPUT.mp4") }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let width = 64, height = 48
        let values = VideoOrientation.playbackTransform(frame: [
            "imageWidth": width, "imageHeight": height,
            "displayTransform": [0.0, 1.25, -0.75, 0, 0.8, -0.1]
        ])
        guard values == [0, 1, -1, 0, 48, 0],
              let transform = values.flatMap(VideoOrientation.affine) else {
            throw failure("Portrait transform did not discard viewport cropping")
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw failure("Writer rejected video input") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("Writer failed to start") }
        writer.startSession(atSourceTime: .zero)
        var raw: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, nil, &raw) == kCVReturnSuccess,
              let buffer = raw else { throw failure("Could not allocate camera-shaped pixels") }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    // Distinct quadrants make the unrotated sensor raster inspectable.
                    let rgba: (UInt8, UInt8, UInt8) = y < height / 2
                        ? (x < width / 2 ? (255, 0, 0) : (0, 255, 0))
                        : (x < width / 2 ? (0, 0, 255) : (255, 255, 0))
                    row[x * 4] = rgba.2; row[x * 4 + 1] = rgba.1
                    row[x * 4 + 2] = rgba.0; row[x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<3 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? failure("Writer stopped accepting frames") }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 5)) else {
                throw writer.error ?? failure("Writer rejected camera pixels")
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 3, timescale: 5))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? failure("Writer failed to finish") }
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw failure("Missing written video track") }
        let size = try await track.load(.naturalSize)
        let stored = try await track.load(.preferredTransform)
        guard size == CGSize(width: width, height: height), stored == transform else {
            throw failure("Writer changed sensor dimensions or lost the preferred transform")
        }
        let bounds = CGRect(origin: .zero, size: size).applying(stored)
        guard bounds == CGRect(x: 0, y: 0, width: height, height: width) else {
            throw failure("Portrait playback escaped the canonical origin")
        }
        let report: [String: Any] = [
            "path": url.path, "naturalSize": [size.width, size.height],
            "preferredTransform": [stored.a, stored.b, stored.c, stored.d, stored.tx, stored.ty],
            "playbackBounds": [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height]
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ValidateVideoOrientation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
