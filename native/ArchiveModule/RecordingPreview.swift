import AVFoundation
import AVKit
import UIKit

/// Owns one foreground player. The capture view has already detached when the
/// user opens Saved sessions, so playback does not compete with an AR session.
final class RecordingPreview: NSObject, UIAdaptivePresentationControllerDelegate {
    enum PreviewError: LocalizedError {
        case unavailable, alreadyOpen, missingRecording, unplayableRecording

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Return to the app and close any open screen before playing a recording."
            case .alreadyOpen: return "A recording is already opening or playing."
            case .missingRecording: return "The saved MP4 could not be found."
            case .unplayableRecording: return "This saved MP4 cannot be played."
            }
        }
    }

    private var preparing = false
    private var controller: RecordingPlayerViewController?
    private var onDismiss: (() -> Void)?
    private let presenterProvider: (() throws -> UIViewController)?

    init(presenterProvider: (() throws -> UIViewController)? = nil) {
        self.presenterProvider = presenterProvider
        super.init()
    }

    func beginPreparation() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !preparing, controller == nil else { throw PreviewError.alreadyOpen }
        _ = try availablePresenter()
        preparing = true
    }

    func cancelPreparation() {
        dispatchPrecondition(condition: .onQueue(.main))
        preparing = false
    }

    func present(asset: AVAsset, onDismiss: @escaping () -> Void) throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard preparing, controller == nil else { throw PreviewError.alreadyOpen }
        let presenter = try availablePresenter()
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        let controller = RecordingPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.modalPresentationStyle = .fullScreen
        controller.view.accessibilityIdentifier = "recording.preview"
        controller.onDismiss = { [weak self] in self?.finish() }
        self.controller = controller
        self.onDismiss = onDismiss
        preparing = false
        presenter.present(controller, animated: true) { [weak self, weak controller] in
            guard let controller, self?.controller === controller else { return }
            controller.player?.play()
        }
        controller.presentationController?.delegate = self
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }

    private func availablePresenter() throws -> UIViewController {
        if let presenterProvider { return try presenterProvider() }
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let presenter = window.rootViewController,
              presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil,
              !presenter.isBeingPresented, !presenter.isBeingDismissed else {
            throw PreviewError.unavailable
        }
        return presenter
    }

    private func finish() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let controller else { return }
        controller.player?.pause()
        controller.player?.replaceCurrentItem(with: nil)
        controller.player = nil
        controller.onDismiss = nil
        self.controller = nil
        preparing = false
        let completion = onDismiss
        onDismiss = nil
        completion?()
    }
}

private final class RecordingPlayerViewController: AVPlayerViewController {
    var onDismiss: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Do not end playback for a temporary interruption or an overlay. Done
        // and interactive dismissal remove the presenting view controller.
        if isBeingDismissed || presentingViewController == nil {
            onDismiss?()
        }
    }
}
