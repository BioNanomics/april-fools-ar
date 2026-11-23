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

    func present(asset: AVAsset, timeline: RecordingPlaybackTimeline? = nil,
                 overlayMessage: String? = nil, onDismiss: @escaping () -> Void) throws {
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
        controller.configureRecordedOverlays(timeline: timeline, message: overlayMessage)
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
        controller.stopRecordedOverlays()
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
    private let recordedOverlay = RecordingPlaybackOverlayView()
    private let overlayToggle = UIButton(type: .system)
    private let overlayStatus = UILabel()
    private var timeline: RecordingPlaybackTimeline?
    private var unavailableMessage: String?
    private var frameOverlayMessage: String?
    private var overlaysEnabled = true
    private var geometry: (size: CGSize, transform: CGAffineTransform)?
    private var geometryTask: Task<Void, Never>?
    private var observedPlayer: AVPlayer?
    private var timeObserver: Any?
    private var boundsObservation: NSKeyValueObservation?
    private var readyObservation: NSKeyValueObservation?
    private var jumpObservation: NSObjectProtocol?
    private var stopped = false

    func configureRecordedOverlays(timeline: RecordingPlaybackTimeline?, message: String?) {
        self.timeline = timeline
        unavailableMessage = message ?? (timeline == nil ? "This recording has no saved overlay data." : nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let content = contentOverlayView {
            recordedOverlay.frame = content.bounds
            recordedOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            content.addSubview(recordedOverlay)
        }
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.78)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "square.3.layers.3d")
        configuration.imagePadding = 7
        overlayToggle.configuration = configuration
        overlayToggle.translatesAutoresizingMaskIntoConstraints = false
        overlayToggle.accessibilityIdentifier = "recording.preview.overlay-toggle"
        overlayToggle.accessibilityLabel = "Recorded overlays"
        overlayToggle.accessibilityHint = "Shows or hides the tag and measurement data saved with this recording."
        overlayToggle.addTarget(self, action: #selector(toggleRecordedOverlays), for: .touchUpInside)
        view.addSubview(overlayToggle)
        overlayStatus.translatesAutoresizingMaskIntoConstraints = false
        overlayStatus.font = .preferredFont(forTextStyle: .caption1)
        overlayStatus.adjustsFontForContentSizeCategory = true
        overlayStatus.numberOfLines = 0
        overlayStatus.textAlignment = .center
        overlayStatus.textColor = .white
        overlayStatus.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        overlayStatus.layer.cornerRadius = 5; overlayStatus.clipsToBounds = true
        overlayStatus.accessibilityIdentifier = "recording.preview.overlay-unavailable"
        view.addSubview(overlayStatus)
        NSLayoutConstraint.activate([
            // AVKit reserves its first safe-area row for Close/AirPlay. Keep
            // the custom control in a separate row even in narrow windows.
            overlayToggle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
            overlayToggle.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            overlayToggle.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            overlayToggle.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            overlayToggle.widthAnchor.constraint(greaterThanOrEqualToConstant: 156),
            overlayToggle.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24),
            overlayStatus.topAnchor.constraint(equalTo: overlayToggle.bottomAnchor, constant: 6),
            overlayStatus.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            overlayStatus.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
        ])
        updateOverlayControl()
        installOverlayObservers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The player updates videoBounds for rotation, aspect-fit letterboxing
        // and changes in the visibility of its own controls.
        refreshRecordedOverlays()
        view.bringSubviewToFront(overlayToggle)
        view.bringSubviewToFront(overlayStatus)
    }

    @objc private func toggleRecordedOverlays() {
        guard timeline != nil, unavailableMessage == nil, !stopped else { return }
        overlaysEnabled.toggle()
        updateOverlayControl()
        refreshRecordedOverlays()
        UIAccessibility.post(notification: .announcement, argument: overlaysEnabled ? "Recorded overlays on" : "Recorded overlays off")
    }

    private func updateOverlayControl() {
        let available = timeline != nil && unavailableMessage == nil
        overlayToggle.isEnabled = available
        overlayToggle.configuration?.title = available ? (overlaysEnabled ? "Overlays on" : "Overlays off") : "Overlays unavailable"
        overlayToggle.accessibilityValue = available ? (overlaysEnabled ? "On" : "Off") : "Unavailable"
        overlayToggle.isSelected = available && overlaysEnabled
        let message = unavailableMessage ?? (overlaysEnabled ? frameOverlayMessage : nil)
        overlayStatus.text = message.map { " \($0) " }
        overlayStatus.isHidden = message == nil
        recordedOverlay.isHidden = !available || !overlaysEnabled
        if !available || !overlaysEnabled { recordedOverlay.clear() }
    }

    private func installOverlayObservers() {
        guard let player, let item = player.currentItem, timeline != nil else { return }
        observedPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            self?.refreshRecordedOverlays(at: time)
        }
        boundsObservation = observe(\.videoBounds, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshRecordedOverlays() }
        }
        readyObservation = observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshRecordedOverlays() }
        }
        jumpObservation = NotificationCenter.default.addObserver(forName: AVPlayerItem.timeJumpedNotification,
            object: item, queue: .main) { [weak self] _ in
                // A seek must replace the previous snapshot even while paused.
                self?.recordedOverlay.clear()
                self?.refreshRecordedOverlays()
            }
        let asset = item.asset
        geometryTask = Task { [weak self, weak player] in
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw RecordingPreview.PreviewError.unplayableRecording
                }
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                guard !Task.isCancelled, let self, !self.stopped,
                      self.observedPlayer === player else { return }
                self.geometry = (size, transform)
                self.refreshRecordedOverlays()
            } catch {
                guard !Task.isCancelled, let self, !self.stopped else { return }
                self.unavailableMessage = "Recorded overlays cannot be aligned with this video's image."
                self.updateOverlayControl()
            }
        }
    }

    private func refreshRecordedOverlays(at time: CMTime? = nil) {
        guard !stopped, overlaysEnabled, unavailableMessage == nil,
              isReadyForDisplay, let timeline, let geometry,
              let content = contentOverlayView, let player else {
            setFrameOverlayMessage(nil)
            recordedOverlay.clear(); return
        }
        let seconds = CMTimeGetSeconds(time ?? player.currentTime())
        guard seconds.isFinite, seconds >= 0, let snapshot = timeline.snapshot(at: seconds) else {
            setFrameOverlayMessage(nil)
            recordedOverlay.clear(); return
        }
        recordedOverlay.frame = content.bounds
        let rect = content.convert(videoBounds, from: view)
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            setFrameOverlayMessage(nil)
            recordedOverlay.clear(); return
        }
        guard RecordingPlaybackOverlayView.imagePoint(.zero, imageSize: snapshot.imageSize,
            naturalSize: geometry.size, preferredTransform: geometry.transform, videoRect: rect) != nil else {
            setFrameOverlayMessage("Recorded overlays are unavailable for this frame's image geometry.")
            recordedOverlay.clear(); return
        }
        setFrameOverlayMessage(nil)
        recordedOverlay.show(snapshot: snapshot, videoRect: rect,
                             naturalSize: geometry.size, preferredTransform: geometry.transform)
    }

    private func setFrameOverlayMessage(_ message: String?) {
        guard frameOverlayMessage != message else { return }
        frameOverlayMessage = message
        updateOverlayControl()
    }

    /// Called before replacing the current item. Removing the periodic observer
    /// from its owning player is mandatory even when playback ended or paused.
    func stopRecordedOverlays() {
        guard !stopped else { return }
        stopped = true
        geometryTask?.cancel(); geometryTask = nil
        if let token = timeObserver, let observedPlayer { observedPlayer.removeTimeObserver(token) }
        timeObserver = nil; observedPlayer = nil
        boundsObservation?.invalidate(); boundsObservation = nil
        readyObservation?.invalidate(); readyObservation = nil
        if let token = jumpObservation { NotificationCenter.default.removeObserver(token) }
        jumpObservation = nil
        recordedOverlay.clear(); timeline = nil; geometry = nil; frameOverlayMessage = nil
    }

    deinit {
        geometryTask?.cancel()
        if let token = timeObserver, let observedPlayer { observedPlayer.removeTimeObserver(token) }
        if let token = jumpObservation { NotificationCenter.default.removeObserver(token) }
        boundsObservation?.invalidate(); readyObservation?.invalidate()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Do not end playback for a temporary interruption or an overlay. Done
        // and interactive dismissal remove the presenting view controller.
        if isBeingDismissed || presentingViewController == nil {
            onDismiss?()
        }
    }
}
