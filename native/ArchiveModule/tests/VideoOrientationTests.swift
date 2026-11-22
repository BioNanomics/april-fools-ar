import XCTest
import CoreGraphics
import AVFoundation
import CoreVideo

final class VideoOrientationTests: XCTestCase {
    func testAllQuarterTurnsIgnoreViewportCropAndZoom() throws {
        let cases: [([Double], [Double])] = [
            ([1.2, 0, 0, 2.1, -0.1, -0.5], [1, 0, 0, 1, 0, 0]),
            ([0, 1.2, -2.1, 0, 0.1, -0.5], [0, 1, -1, 0, 1440, 0]),
            ([-1.2, 0, 0, -2.1, 2, 2], [-1, 0, 0, -1, 1920, 1440]),
            ([0, -1.2, 2.1, 0, 0, 0], [0, -1, 1, 0, 0, 1920]),
        ]
        for (display, expected) in cases {
            let values = try XCTUnwrap(VideoOrientation.playbackTransform(frame: ["imageWidth":1920, "imageHeight":1440, "displayTransform":display]))
            XCTAssertEqual(values, expected)
            let transform = try XCTUnwrap(VideoOrientation.affine(values))
            let corners = [CGPoint(x: 0,y: 0), CGPoint(x: 1920,y: 0), CGPoint(x: 1920,y: 1440), CGPoint(x: 0,y: 1440)].map { $0.applying(transform) }
            XCTAssertEqual(corners.map(\.x).min(), 0)
            XCTAssertEqual(corners.map(\.y).min(), 0)
        }
    }
    func testStoredFirstFrameOrientationWinsOverLaterViewport() {
        let manifest: [String: Any] = ["videoContent": ["playbackTransform": [0,1,-1,0,1440,0]]]
        XCTAssertEqual(VideoOrientation.playbackTransform(manifest: manifest, firstFrame: ["imageWidth":1920,"imageHeight":1440,"displayTransform":[1,0,0,1,0,0]]), [0,1,-1,0,1440,0])
    }
    func testMalformedTransformsAreNotGuessed() {
        for transform in [[1.0,0,0,-1,0,0], [1,1,0,1,0,0], [0,0,0,0,0,0], [Double.nan,0,0,1,0,0]] {
            XCTAssertNil(VideoOrientation.playbackTransform(frame: ["imageWidth":1920,"imageHeight":1440,"displayTransform":transform]))
        }
        XCTAssertNil(VideoOrientation.playbackTransform(frame: ["imageWidth":0,"imageHeight":1440,"interfaceOrientation":1]))
        XCTAssertEqual(VideoOrientation.playbackTransform(frame: ["imageWidth":1920,"imageHeight":1440,"interfaceOrientation":1]), [0,1,-1,0,1440,0])
    }
    func testAssetWriterPersistsPortraitMatrixWithoutRotatingPixels() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48])
        let values = try XCTUnwrap(VideoOrientation.playbackTransform(frame: ["imageWidth":64,"imageHeight":48,"displayTransform":[0,1,-1,0,1,0]]))
        input.transform = try XCTUnwrap(VideoOrientation.affine(values))
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var raw: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA, nil, &raw), kCVReturnSuccess)
        let buffer = try XCTUnwrap(raw)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, 128, CVPixelBufferGetBytesPerRow(buffer) * 48) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        XCTAssertTrue(adaptor.append(buffer, withPresentationTime: .zero))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(size.width, 64)
        XCTAssertEqual(size.height, 48)
        XCTAssertEqual(transform, CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0))
    }

}
