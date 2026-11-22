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
