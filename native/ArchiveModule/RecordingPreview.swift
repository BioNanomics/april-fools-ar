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
                 overlayMessage: String? = nil, startSeconds: Double = 0, startPaused: Bool = false, onDismiss: @escaping () -> Void) throws {
        dispatchPrecondition(condition: .onQueue(.main))
        guard preparing, controller == nil else { throw PreviewError.alreadyOpen }
        guard startSeconds.isFinite, startSeconds >= 0 else { throw PreviewError.unplayableRecording }
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
            if startSeconds > 0 || startPaused {
                controller.player?.seek(to: CMTime(seconds: startSeconds, preferredTimescale: 600_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak controller] finished in
                    if finished && !startPaused { controller?.player?.play() }
                }
            } else { controller.player?.play() }
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
    private let viewModeControl = UISegmentedControl(items: ["Recorded", "Camera", "Depth", "Confidence"])
    private let rasterView = UIImageView()
    private let rasterStatus = UILabel()
    private let rasterQueue = DispatchQueue(label: "com.aprilfoolsar.playback-raster", qos: .userInitiated)
    private var rasterGeneration = 0
    private var rasterLoadInFlight = false
    private var desiredRaster: (sample: RecordingPlaybackRasterSample, mode: String, key: String)?
    private var resolvedRasterKey: String?
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
            rasterView.isUserInteractionEnabled = false
            rasterView.contentMode = .scaleToFill
            rasterView.alpha = 0.88
            rasterView.isHidden = true
            rasterView.layer.anchorPoint = .zero
            rasterView.accessibilityIdentifier = "recording.preview.depth-image"
            content.addSubview(rasterView)
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
        overlayToggle.accessibilityHint = "Shows or hides saved annotations and sensor views."
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
        viewModeControl.translatesAutoresizingMaskIntoConstraints = false
        viewModeControl.selectedSegmentIndex = 0
        viewModeControl.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        viewModeControl.selectedSegmentTintColor = .systemBlue
        viewModeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        viewModeControl.accessibilityIdentifier = "recording.preview.view-mode"
        viewModeControl.accessibilityLabel = "Playback view"
        viewModeControl.accessibilityHint = "Recorded follows saved view changes. Choose Camera, Depth, or Confidence to inspect saved data."
        viewModeControl.addTarget(self, action: #selector(changePlaybackView), for: .valueChanged)
        view.addSubview(viewModeControl)
        rasterStatus.translatesAutoresizingMaskIntoConstraints = false
        rasterStatus.font = .preferredFont(forTextStyle: .caption1)
        rasterStatus.adjustsFontForContentSizeCategory = true
        rasterStatus.numberOfLines = 0
        rasterStatus.textAlignment = .center
        rasterStatus.textColor = .white
        rasterStatus.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        rasterStatus.accessibilityIdentifier = "recording.preview.raster-status"
        rasterStatus.isHidden = true
        view.addSubview(rasterStatus)
        NSLayoutConstraint.activate([
            // AVKit reserves its first safe-area row for Close/AirPlay. Keep
            // the custom control in a separate row even in narrow windows.
            overlayToggle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
            overlayToggle.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            overlayToggle.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            overlayToggle.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            overlayToggle.widthAnchor.constraint(greaterThanOrEqualToConstant: 156),
            overlayToggle.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24),
            viewModeControl.topAnchor.constraint(equalTo: overlayToggle.bottomAnchor, constant: 8),
            viewModeControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            viewModeControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            viewModeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            rasterStatus.topAnchor.constraint(equalTo: viewModeControl.bottomAnchor, constant: 6),
            rasterStatus.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            rasterStatus.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
            overlayStatus.topAnchor.constraint(equalTo: rasterStatus.bottomAnchor, constant: 6),
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
        view.bringSubviewToFront(viewModeControl)
        view.bringSubviewToFront(rasterStatus)
        view.bringSubviewToFront(overlayStatus)
    }

    @objc private func toggleRecordedOverlays() {
        guard timeline != nil, unavailableMessage == nil, !stopped else { return }
        overlaysEnabled.toggle()
        updateOverlayControl()
        refreshRecordedOverlays()
        UIAccessibility.post(notification: .announcement, argument: overlaysEnabled ? "Recorded overlays on" : "Recorded overlays off")
    }

    @objc private func changePlaybackView() {
        invalidateRaster()
        refreshRecordedOverlays()
    }

    private func updateOverlayControl() {
        let available = timeline != nil && unavailableMessage == nil
        overlayToggle.isEnabled = available
        overlayToggle.configuration?.title = available ? (overlaysEnabled ? "Overlays on" : "Overlays off") : "Overlays unavailable"
        overlayToggle.accessibilityValue = available ? (overlaysEnabled ? "On" : "Off") : "Unavailable"
        overlayToggle.isSelected = available && overlaysEnabled
        viewModeControl.isEnabled = available && overlaysEnabled
        viewModeControl.setEnabled(available, forSegmentAt: 0)
        viewModeControl.setEnabled(available, forSegmentAt: 1)
        viewModeControl.setEnabled(available && timeline?.hasDepthSamples == true, forSegmentAt: 2)
        viewModeControl.setEnabled(available && timeline?.hasConfidenceSamples == true, forSegmentAt: 3)
        let message = unavailableMessage ?? (overlaysEnabled ? frameOverlayMessage : nil)
        overlayStatus.text = message.map { " \($0) " }
        overlayStatus.isHidden = message == nil
        recordedOverlay.isHidden = !available || !overlaysEnabled
        if !available || !overlaysEnabled {
            recordedOverlay.clear()
            invalidateRaster()
            setRasterStatus(nil)
        }
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
                self?.invalidateRaster()
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
            invalidateRaster()
            setRasterStatus(nil)
            recordedOverlay.clear(); return
        }
        let seconds = CMTimeGetSeconds(time ?? player.currentTime())
        guard seconds.isFinite, seconds >= 0, let snapshot = timeline.snapshot(at: seconds) else {
            setFrameOverlayMessage(nil)
            invalidateRaster()
            setRasterStatus(nil)
            recordedOverlay.clear(); return
        }
        recordedOverlay.frame = content.bounds
        let rect = content.convert(videoBounds, from: view)
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            setFrameOverlayMessage(nil)
            invalidateRaster()
            recordedOverlay.clear(); return
        }
        guard RecordingPlaybackOverlayView.imagePoint(.zero, imageSize: snapshot.imageSize,
            naturalSize: geometry.size, preferredTransform: geometry.transform, videoRect: rect) != nil else {
            setFrameOverlayMessage("Recorded overlays are unavailable for this frame's image geometry.")
            invalidateRaster()
            recordedOverlay.clear(); return
        }
        setFrameOverlayMessage(nil)
        let choices = [snapshot.recordedPreviewMode ?? "camera", "camera", "depth", "confidence"]
        let selection = min(max(viewModeControl.selectedSegmentIndex, 0), choices.count - 1)
        let mode = choices[selection]
        viewModeControl.accessibilityValue = selection == 0 ? "Recorded, \(mode.capitalized)" : viewModeControl.titleForSegment(at: selection)
        recordedOverlay.showsTags = mode == "camera"
        if mode == "camera" {
            invalidateRaster()
            setRasterStatus(selection == 0 && snapshot.recordedPreviewMode == nil
                ? "Original view changes unavailable. Choose a view to inspect saved maps." : nil)
        } else if let sample = snapshot.rasterSample {
            if alignRaster(sample.imageSize, naturalSize: geometry.size, transform: geometry.transform, videoRect: rect) {
                requestRaster(sample: sample, mode: mode)
            } else {
                invalidateRaster()
                setRasterStatus("Saved maps cannot be aligned with this frame's image.")
            }
        } else {
            invalidateRaster()
            setRasterStatus("No saved \(mode == "depth" ? "depth" : "confidence") sample at this point.")
        }
        recordedOverlay.show(snapshot: snapshot, videoRect: rect,
                             naturalSize: geometry.size, preferredTransform: geometry.transform)
    }

    private func alignRaster(_ imageSize: CGSize, naturalSize: CGSize, transform: CGAffineTransform, videoRect: CGRect) -> Bool {
        func mapped(_ point: CGPoint) -> CGPoint? {
            RecordingPlaybackOverlayView.imagePoint(point, imageSize: imageSize, naturalSize: naturalSize,
                preferredTransform: transform, videoRect: videoRect)
        }
        guard let origin = mapped(.zero), let x = mapped(CGPoint(x: imageSize.width, y: 0)),
              let y = mapped(CGPoint(x: 0, y: imageSize.height)), imageSize.width > 0, imageSize.height > 0 else {
            return false
        }
        rasterView.bounds = CGRect(origin: .zero, size: imageSize)
        rasterView.layer.position = .zero
        rasterView.transform = CGAffineTransform(a: (x.x-origin.x)/imageSize.width, b: (x.y-origin.y)/imageSize.width,
            c: (y.x-origin.x)/imageSize.height, d: (y.y-origin.y)/imageSize.height, tx: origin.x, ty: origin.y)
        return true
    }

    private func setRasterStatus(_ message: String?) {
        rasterStatus.text = message.map { " \($0) " }
        rasterStatus.isHidden = message == nil
    }

    private func invalidateRaster() {
        if desiredRaster != nil || resolvedRasterKey != nil { rasterGeneration += 1 }
        desiredRaster = nil
        resolvedRasterKey = nil
        rasterView.image = nil
        rasterView.isHidden = true
    }

    private func requestRaster(sample: RecordingPlaybackRasterSample, mode: String) {
        let key = mode + ":" + sample.id
        if desiredRaster?.key != key {
            invalidateRaster()
            rasterGeneration += 1
            desiredRaster = (sample, mode, key)
            setRasterStatus("Loading saved \(mode == "depth" ? "depth" : "confidence")…")
        }
        startRasterLoadIfNeeded()
    }

    private func startRasterLoadIfNeeded() {
        guard !stopped, !rasterLoadInFlight, let request = desiredRaster,
              resolvedRasterKey != request.key, let timeline else { return }
        rasterLoadInFlight = true
        let generation = rasterGeneration
        rasterQueue.async { [weak self] in
            let result = Result { try autoreleasepool { try timeline.rasterImage(for: request.sample, mode: request.mode) } }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rasterLoadInFlight = false
                guard !self.stopped else { return }
                if generation == self.rasterGeneration, self.desiredRaster?.key == request.key {
                    self.resolvedRasterKey = request.key
                    switch result {
                    case .success(let image):
                        self.rasterView.image = image
                        self.rasterView.isHidden = false
                        self.setRasterStatus(nil)
                    case .failure:
                        self.rasterView.image = nil
                        self.rasterView.isHidden = true
                        self.setRasterStatus("Saved \(request.mode == "depth" ? "depth" : "confidence") data is unavailable for this sample.")
                    }
                }
                self.startRasterLoadIfNeeded()
            }
        }
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
        invalidateRaster()
        setRasterStatus(nil)
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
