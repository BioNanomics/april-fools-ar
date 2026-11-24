import AVFoundation
import AVKit
import CoreGraphics
import CoreVideo
import CryptoKit
import UIKit
import XCTest

/// Exercises the actual player and asynchronous raster delivery using tiny,
/// synthetic files. The fixture does not contain user footage or sensor truth.
@MainActor
final class RecordingPlaybackViewModeTests: XCTestCase {
    private let sensorSize = CGSize(width: 80, height: 60)
    private let portraitTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 60, ty: 0)

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func eventually(_ message: String, timeout: Double = 5,
                            _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(predicate(), message)
    }

    private func seek(_ player: AVPlayer, seconds: Double) async {
        await withCheckedContinuation { continuation in
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }

    private func movie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(sensorSize.width), AVVideoHeightKey: Int(sensorSize.height),
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = portraitTransform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                         sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var raw: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, Int(sensorSize.width), Int(sensorSize.height),
            kCVPixelFormatType_32BGRA, nil, &raw), kCVReturnSuccess)
        let buffer = try XCTUnwrap(raw)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 80, CVPixelBufferGetBytesPerRow(buffer) * Int(sensorSize.height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for index in 0..<30 {
            try await eventually("Video writer accepts the synthetic frame") { input.isReadyForMoreMediaData }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func fixture(at folder: URL) throws -> RecordingPlaybackTimeline {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("depth"),
                                                withIntermediateDirectories: true)
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let intrinsics: [Double] = [70, 0, 0, 0, 70, 0, 40, 30, 1]
        var payloads = [String: Data]()
        var frames = [[String: Any]]()
        for index in 0..<5 {
            let seconds = Double(index) / 5
            var row: [String: Any] = [
                "frameId": "f\(index)", "segmentId": "A", "timestamp": 1000 + seconds,
                "videoPTSSeconds": seconds, "videoAppended": true, "tracking": "normal",
                "imageWidth": Int(sensorSize.width), "imageHeight": Int(sensorSize.height),
                "cameraToWorldColumnMajor": identity, "intrinsicsColumnMajor": intrinsics,
                "displayTransform": [0, 1, -1, 0, 1, 0],
                "previewMode": index == 1 ? "depth" : index == 2 ? "confidence" : "camera",
            ]
            if index == 1 || index == 2 {
                let depthPath = "depth/f\(index).f32"
                let confidencePath = "depth/f\(index).confidence.u8"
                var depth = Data()
                for sample in 0..<12 {
                    var bits = Float(index + sample % 4).bitPattern.littleEndian
                    withUnsafeBytes(of: &bits) { depth.append(contentsOf: $0) }
                }
                payloads[depthPath] = depth
                payloads[confidencePath] = Data((0..<12).map { UInt8(($0 + index) % 3) })
                row["depthPath"] = depthPath
                row["confidencePath"] = confidencePath
                row["depthWidth"] = 4
                row["depthHeight"] = 3
                row["depthAvailable"] = true
                row["depthEncoding"] = "float32-little-endian-packed-camera-plane-Z-meters"
                row["confidenceEncoding"] = "uint8-packed-ARConfidenceLevel-0-low-1-medium-2-high"
            }
            frames.append(row)
        }
        var frameData = Data()
        for row in frames {
            frameData.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
            frameData.append(10)
        }
        payloads["frames.jsonl"] = frameData
        payloads["events.jsonl"] = Data()
        for (path, bytes) in payloads {
            try bytes.write(to: folder.appendingPathComponent(path))
        }
        let manifest: [String: Any] = [
            "schemaVersion": 1, "finalized": true, "firstARFrameTimestamp": 1000.0,
            "fileInventory": payloads.keys.sorted().map { path in
                ["path": path, "bytes": payloads[path]!.count,
                 "sha256": SHA256.hash(data: payloads[path]!).map { String(format: "%02x", $0) }.joined()] as [String: Any]
            },
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: folder.appendingPathComponent("manifest.json"))
        return try RecordingPlaybackTimeline.load(folderURL: folder)
    }

    private func assertPortraitAlignment(_ raster: UIImageView, controller: AVPlayerViewController,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
        for unit in [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
            let sensor = CGPoint(x: unit.x * sensorSize.width, y: unit.y * sensorSize.height)
            let expected = try XCTUnwrap(RecordingPlaybackOverlayView.imagePoint(sensor,
                imageSize: sensorSize, naturalSize: sensorSize, preferredTransform: portraitTransform,
                videoRect: controller.videoBounds), file: file, line: line)
            let local = CGPoint(x: raster.bounds.minX + unit.x * raster.bounds.width,
                                y: raster.bounds.minY + unit.y * raster.bounds.height)
            let actual = raster.convert(local, to: controller.view)
            XCTAssertEqual(actual.x, expected.x, accuracy: 2, "Raster follows the video's portrait transform", file: file, line: line)
            XCTAssertEqual(actual.y, expected.y, accuracy: 2, "Raster follows the video's portrait transform", file: file, line: line)
        }
    }

    func testRecordedAndExplicitViewsUseSavedMapsAndClearOnSeekAndDismissal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,
                                                                                    isDirectory: true)
        let timeline = try fixture(at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movieURL = folder.appendingPathComponent("test.mp4")
        try await movie(at: movieURL)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { presenter.dismiss(animated: false); window.isHidden = true }
        let preview = RecordingPreview(presenterProvider: { presenter })
        var dismissed = false
        try preview.beginPreparation()
        try preview.present(asset: AVURLAsset(url: movieURL), timeline: timeline) { dismissed = true }
        let controller = try XCTUnwrap(presenter.presentedViewController as? AVPlayerViewController)
        let player = try XCTUnwrap(controller.player)
        try await eventually("Player is ready") { player.currentItem?.status == .readyToPlay }
        try await eventually("Player has appeared") { controller.view.window != nil && !controller.isBeingPresented }
        player.pause()
        let modes = try XCTUnwrap(descendants(controller.view).first {
            $0.accessibilityIdentifier == "recording.preview.view-mode"
        } as? UISegmentedControl)
        let raster = try XCTUnwrap(descendants(controller.view).first {
            $0.accessibilityIdentifier == "recording.preview.depth-image"
        } as? UIImageView)
        XCTAssertEqual(modes.numberOfSegments, 4)
        XCTAssertEqual(modes.selectedSegmentIndex, 0)
        XCTAssertEqual(modes.accessibilityLabel, "Playback view")
        XCTAssertTrue(modes.isEnabledForSegment(at: 2))
        XCTAssertTrue(modes.isEnabledForSegment(at: 3))

        await seek(player, seconds: 0.25)
        try await eventually("Recorded mode replays the saved depth view") { raster.image != nil && !raster.isHidden }
        let depthPixels = try XCTUnwrap(raster.image?.pngData())
        try assertPortraitAlignment(raster, controller: controller)
        XCTAssertEqual(player.rate, 0)

        modes.selectedSegmentIndex = 3
        modes.sendActions(for: .valueChanged)
        try await eventually("Confidence selects a different saved raster") {
            !raster.isHidden && raster.image?.pngData() != nil && raster.image?.pngData() != depthPixels
        }
        try assertPortraitAlignment(raster, controller: controller)

        modes.selectedSegmentIndex = 1
        modes.sendActions(for: .valueChanged)
        XCTAssertTrue(raster.isHidden || raster.image == nil, "Camera view clears the raster")
        // A queued decode from an immediately superseded selection must not
        // resurrect its raster after Camera has become the selected view.
        modes.selectedSegmentIndex = 2
        modes.sendActions(for: .valueChanged)
        modes.selectedSegmentIndex = 1
        modes.sendActions(for: .valueChanged)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(raster.isHidden || raster.image == nil)

        modes.selectedSegmentIndex = 2
        modes.sendActions(for: .valueChanged)
        try await eventually("Depth is restored") { raster.image != nil && !raster.isHidden }
        await seek(player, seconds: 0)
        try await eventually("Backward seek before the first map removes the later raster") {
            raster.isHidden || raster.image == nil
        }
        await seek(player, seconds: 0.25)
        try await eventually("Seeking back restores the matching saved depth map") { raster.image != nil && !raster.isHidden }

        modes.selectedSegmentIndex = 0
        modes.sendActions(for: .valueChanged)
        await seek(player, seconds: 0.65)
        try await eventually("Recorded camera mode hides the depth/confidence layer") {
            raster.isHidden || raster.image == nil
        }
        await seek(player, seconds: 0.45)
        try await eventually("Recorded confidence mode restores its saved sample") { raster.image != nil && !raster.isHidden }
        presenter.dismiss(animated: false)
        try await eventually("Dismissal releases player ownership") { dismissed }
        XCTAssertNil(controller.player)
        XCTAssertNil(player.currentItem)
        XCTAssertNil(raster.image, "Dismissal releases the retained raster")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(raster.image, "An asynchronous completion cannot restore a dismissed raster")
        XCTAssertNoThrow(try preview.beginPreparation())
        preview.cancelPreparation()
    }

    func testOptionalPrivateRecordingShowsDepthAndConfidenceOnItsActualVideo() async throws {
        guard let folder = Bundle(for: Self.self).url(forResource: "recorded-fixture", withExtension: nil) else {
            throw XCTSkip("Pass private --recording-folder and --recording-video paths to the simulator runner.")
        }
        let timeline = try RecordingPlaybackTimeline.load(folderURL: folder)
        XCTAssertTrue(timeline.hasDepthSamples, "The private fixture includes recorded depth samples")
        XCTAssertTrue(timeline.hasConfidenceSamples, "The private fixture includes recorded confidence samples")
        let asset = AVURLAsset(url: folder.appendingPathComponent("recording.mp4"))
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertTrue(duration.isFinite && duration > 0.5)
        let sampleTime = 0.5
        let snapshot = try XCTUnwrap(timeline.snapshot(at: sampleTime))
        let sample = try XCTUnwrap(snapshot.rasterSample, "A matching recorded map exists near 0.5 seconds")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { presenter.dismiss(animated: false); window.isHidden = true }
        let preview = RecordingPreview(presenterProvider: { presenter })
        try preview.beginPreparation()
        try preview.present(asset: asset, timeline: timeline) {}
        let controller = try XCTUnwrap(presenter.presentedViewController as? AVPlayerViewController)
        let player = try XCTUnwrap(controller.player)
        try await eventually("Private player is ready") { player.currentItem?.status == .readyToPlay }
        try await eventually("Private player is presented") { controller.view.window != nil && !controller.isBeingPresented }
        player.pause()
        await seek(player, seconds: sampleTime)
        let modes = try XCTUnwrap(descendants(controller.view).first {
            $0.accessibilityIdentifier == "recording.preview.view-mode"
        } as? UISegmentedControl)
        let raster = try XCTUnwrap(descendants(controller.view).first {
            $0.accessibilityIdentifier == "recording.preview.depth-image"
        } as? UIImageView)

        for (mode, selection) in [("depth", 2), ("confidence", 3)] {
            // Reading here establishes the expected source sample. The player
            // independently loads it through its asynchronous delivery path.
            let expected = try XCTUnwrap(try timeline.rasterImage(for: sample, mode: mode).pngData())
            modes.selectedSegmentIndex = selection
            modes.sendActions(for: .valueChanged)
            try await eventually("Private \(mode) sample is visible") {
                !raster.isHidden && raster.image?.pngData() == expected
            }
            XCTAssertEqual(modes.selectedSegmentIndex, selection)
            // The glass selection indicator animates independently of the
            // image load. Let it settle before preserving visual evidence.
            try await Task.sleep(nanoseconds: 400_000_000)
            controller.view.layoutIfNeeded()
            for unit in [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
                let sensor = CGPoint(x: unit.x * sample.imageSize.width, y: unit.y * sample.imageSize.height)
                let mapped = try XCTUnwrap(RecordingPlaybackOverlayView.imagePoint(sensor,
                    imageSize: sample.imageSize, naturalSize: naturalSize, preferredTransform: transform,
                    videoRect: controller.videoBounds))
                let local = CGPoint(x: raster.bounds.minX + unit.x * raster.bounds.width,
                                    y: raster.bounds.minY + unit.y * raster.bounds.height)
                let actual = raster.convert(local, to: controller.view)
                XCTAssertEqual(actual.x, mapped.x, accuracy: 2)
                XCTAssertEqual(actual.y, mapped.y, accuracy: 2)
            }
            XCTAssertEqual(player.rate, 0)
            let screenshot = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "Private recording — \(mode) playback"
            attachment.lifetime = .keepAlways
            add(attachment)
            let location = FileManager.default.temporaryDirectory
                .appendingPathComponent("recording-playback-private-\(mode).png")
            try XCTUnwrap(screenshot.pngData()).write(to: location)
            print("PLAYBACK_OVERLAY_PNG \(location.path)")
        }
    }
}
