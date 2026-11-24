import AVFoundation
import AVKit
import UIKit
import XCTest

@MainActor
final class RecordingPreviewTests: XCTestCase {
    func testOnlyOnePreparationAndCancellationAllowsRetry() throws {
        let preview = RecordingPreview(presenterProvider: { UIViewController() })
        try preview.beginPreparation()
        XCTAssertThrowsError(try preview.beginPreparation())
        preview.cancelPreparation()
        XCTAssertNoThrow(try preview.beginPreparation())
        preview.cancelPreparation()
    }

    func testPresentationFailureCanBeRetried() throws {
        var available = false
        let preview = RecordingPreview(presenterProvider: {
            guard available else { throw RecordingPreview.PreviewError.unavailable }
            return UIViewController()
        })
        XCTAssertThrowsError(try preview.beginPreparation())
        available = true
        XCTAssertNoThrow(try preview.beginPreparation())
        available = false
        XCTAssertThrowsError(try preview.present(asset: AVMutableComposition(), onDismiss: {}))
        preview.cancelPreparation()
        available = true
        XCTAssertNoThrow(try preview.beginPreparation())
        preview.cancelPreparation()
    }

    func testInvalidObservationTimesCannotPresentAPlayerAndPreparationCanBeRetried() throws {
        let presenter = UIViewController()
        let preview = RecordingPreview(presenterProvider: { presenter })
        for seconds in [-1, Double.nan, Double.infinity, -Double.infinity] {
            try preview.beginPreparation()
            XCTAssertThrowsError(try preview.present(asset: AVMutableComposition(), startSeconds: seconds,
                                                     startPaused: true, onDismiss: {})) { error in
                guard case RecordingPreview.PreviewError.unplayableRecording = error else {
                    return XCTFail("Invalid saved observation time must report an unplayable recording: \(error)")
                }
            }
            XCTAssertNil(presenter.presentedViewController)
            preview.cancelPreparation()
        }
        XCTAssertNoThrow(try preview.beginPreparation())
        preview.cancelPreparation()
    }

    func testObservationPreviewSeeksToRequestedTimeAndRemainsPaused() async throws {
        let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: movieURL) }
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
        try preview.present(asset: AVURLAsset(url: movieURL), startSeconds: 0.6, startPaused: true) { dismissed = true }
        let controller = try XCTUnwrap(presenter.presentedViewController as? AVPlayerViewController)
        let player = try XCTUnwrap(controller.player)
        try await eventually("Player completes presentation and exact observation seek") {
            player.currentItem?.status == .readyToPlay && !controller.isBeingPresented &&
                abs(CMTimeGetSeconds(player.currentTime()) - 0.6) < 0.01
        }
        XCTAssertEqual(player.rate, 0, "Opening a seen-tag observation must not autoplay past its source time")
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(CMTimeGetSeconds(player.currentTime()), 0.6, accuracy: 0.01)
        XCTAssertEqual(player.rate, 0)
        presenter.dismiss(animated: false)
        try await eventually("Observation preview relinquishes player on dismissal") { dismissed }
        XCTAssertNil(controller.player)
        XCTAssertNil(player.currentItem)
        XCTAssertNoThrow(try preview.beginPreparation())
        preview.cancelPreparation()
    }

    private func eventually(_ message: String, timeout: Double = 4, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate(), message)
    }

    /// A synthetic one-second movie gives AVPlayer a real seekable timebase;
    /// an empty composition cannot establish that a requested seek completed.
    private func movie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
        ])
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
        for frame in 0..<5 {
            try await eventually("Synthetic movie writer accepts a frame") { input.isReadyForMoreMediaData }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 5)))
        }
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    func testDismissalClearsPlayerAndAllowsAnotherPreview() async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let preview = RecordingPreview(presenterProvider: { presenter })
        let finished = expectation(description: "Native preview settled after dismissal")
        try preview.beginPreparation()
        try preview.present(asset: AVMutableComposition()) { finished.fulfill() }
        let playerController = try XCTUnwrap(presenter.presentedViewController as? AVPlayerViewController)
        let player = try XCTUnwrap(playerController.player)
        XCTAssertNotNil(player.currentItem)
        XCTAssertEqual(playerController.videoGravity, .resizeAspect)
        XCTAssertFalse(playerController.allowsPictureInPicturePlayback)
        XCTAssertEqual(playerController.view.accessibilityIdentifier, "recording.preview")
        XCTAssertThrowsError(try preview.beginPreparation())

        let shown = expectation(description: "Player presentation completed")
        if let transition = playerController.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { _ in shown.fulfill() }
        } else {
            shown.fulfill()
        }
        await fulfillment(of: [shown], timeout: 3)
        presenter.dismiss(animated: false)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertNil(playerController.player)
        XCTAssertNil(player.currentItem)
        XCTAssertEqual(player.rate, 0)
        XCTAssertNoThrow(try preview.beginPreparation())
        preview.cancelPreparation()
    }
}
