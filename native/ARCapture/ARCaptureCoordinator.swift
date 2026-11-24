import Foundation
import ARKit
import RealityKit
import UIKit
import simd

fileprivate struct SpatialRenderSnapshot {
    let generation: Int
    let mode: SpatialMode
    let visible: Bool
    let planes: [SpatialPlane]
    let measurements: [SpatialMeasurement]
    let pendingPoints: [SIMD3<Float>]
    let automaticTagHeights: [TagHeightVector]
    let selectedFloorID: String?
    let pendingSelectedFloorID: String?
    let isTrackingNormal: Bool
    let cameraToWorld: simd_float4x4
    let intrinsics: simd_float3x3
    let imageSize: CGSize
    let displayTransform: CGAffineTransform
    let timestamp: Double
    let showImperialHeight: Bool
}

final class ARCaptureCoordinator: NSObject, ARSessionDelegate {
    static let shared = ARCaptureCoordinator()
    private let captureQueue = DispatchQueue(label: "AprilFoolsAR.capture.frames", qos: .userInitiated)
    private let tagQueue = DispatchQueue(label: "AprilFoolsAR.apriltag.detect", qos: .userInitiated)
    private let savedSessionQueue = DispatchQueue(label: "AprilFoolsAR.saved-sessions", qos: .utility)
    // Detector ownership stays exclusively on tagQueue; job/status ownership stays on captureQueue.
    private var tagDetector: AFTagDetector?
    private var tagInFlight = false
    private var tagPendingFrameID: String?
    private var tagPendingRecorderID: String?
    private var tagGeneration = 0
    private var lastTagResultTimestamp: Double?
    private var tagState = "initializing"
    private var tagIDs = [Int]()
    private var tagLatencyMilliseconds: Double?
    private var tagAnalyzedFrames = 0
    private var tagSkippedFrames = 0
    private var tagLateRecordingResults = 0
    private var tagResultFrameID: String?
    private var tagError: String?
    private var debugSettings = TagDebugSettings.load()
    private var debugMode = true
    private var selectedTagID: Int?
    private var latestTagDetections = [[String: Any]]()
    private var latestTagDisplayTransform = CGAffineTransform.identity
    private var latestTagImageSize = CGSize(width: 1, height: 1)
    private var latestTagIntrinsics: [Double]?
    private var tagCompletionTimes = [Double]()
    private var lastJSEmissionTime = 0.0
    private weak var host: ARCaptureView?
    private var session: ARSession?
    private var recorder: CaptureRecorder?
    private var finalizingRecorder: CaptureRecorder?
    private var latestFrame: ARFrame?
    private var frameCounter = 0
    private var segment = UUID().uuidString
    private var viewport = CGSize(width: 1, height: 1)
    private var orientation = UIInterfaceOrientation.portrait
    private var tracking = "unavailable"
    private var trackingReason = "initializing"
    private var depthAvailable = false
    private var previewMode = "camera"
    private var displayZoom = PreviewZoom.minimum
    private var points = [[String: Any]]()
    private var worldPoints = [SIMD3<Float>]()
    private lazy var spatialState = SpatialMeasurementState(segmentID: segment, levelFloorWithGravity: debugSettings.levelFloorWithGravity)
    private var floorCandidates = [SpatialPlane]()
    private struct CachedFloorFit {
        let segmentID: String
        let planeID: String
        let frameID: String
        let timestamp: Double
        let fit: FloorPlaneFit.Result
    }
    private var cachedFloorFit: CachedFloorFit?
    private var fittingCandidateID: String?
    private var lastFloorFitAttempt = -Double.infinity
    private var showFloorPlanes = true
    private let spatialRenderLock = NSLock()
    private var spatialRenderGeneration = 0
    private var spatialRenderScheduled = false
    private var pendingSpatialRender: SpatialRenderSnapshot?
    private var lastMeasurement: [String: Any] = ["pointCount": 0, "distanceMeters": NSNull(), "verticalMeters": NSNull()]
    private var lastError: String?
    private var counters: [String: Any] = ["framesWritten": 0, "depthFrames": 0, "videoFrames": 0, "bytesWritten": 0]
    private var droppedFrames = 0
    private var recordingStartedAt: Date?
    private var lastStatusTime = 0.0
    private var lastDepthPreviewTime = 0.0
    private var lastGeometryTime = 0.0
    private var lastTrackingKey = ""
    private var finalizing = false
    private var resetting = false
    private var minimumFrameTimestamp = 0.0
    private var backgroundObserver: NSObjectProtocol?
    // Accessed only on the main queue.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var onStatus: (([String: Any]) -> Void)?

    override init() {
        super.init()
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.backgroundTask == .invalid {
                self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finalize AR capture") { [weak self] in
                    guard let self else { return }
                    self.captureQueue.async {
                        self.recorder?.backgroundExecutionExpired()
                        self.finalizingRecorder?.backgroundExecutionExpired()
                        self.lastError = "Background capture finalization expired. The session remains unfinalized."
                        self.emitStatus()
                    }
                    self.endBackgroundTask()
                }
            }
            self.captureQueue.async {
                self.recorder?.event(["type": "applicationBackgrounded", "timestamp": self.latestFrame?.timestamp ?? 0])
                self.beginSegment(reason: "application backgrounded")
                if self.recorder != nil { self.stopSession { _ in } }
                else if !self.finalizing { DispatchQueue.main.async { self.endBackgroundTask() } }
            }
        }
    }

    static var lidarSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    func attach(_ view: ARCaptureView) {
        host = view
        let arSession = view.arView.session
        arSession.delegate = self
        arSession.delegateQueue = captureQueue
        captureQueue.async {
            self.session = arSession; self.invalidateAprilTags()
            let enabled = self.debugMode, zoom = self.displayZoom, mode = self.previewMode
            let hideTags = mode != "camera" || (!enabled && self.spatialState.mode == .selectFloor)
            DispatchQueue.main.async {
                view.setDebugMode(enabled); view.setDisplayZoom(zoom)
                view.depthView.isHidden = mode == "camera"
                view.tagOverlay.isHidden = hideTags
            }
        }
        guard ARWorldTrackingConfiguration.isSupported else {
            captureQueue.async { self.lastError = "ARKit live capture requires a supported iPhone or iPad."; self.emitStatus() }
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]
        if Self.lidarSupported { config.frameSemantics.insert(.sceneDepth) }
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats.filter { $0.framesPerSecond == 30 && $0.imageResolution.width <= 1920 }
        if let format = formats.sorted(by: { $0.imageResolution.width > $1.imageResolution.width }).first { config.videoFormat = format }
        arSession.run(config)
        captureQueue.async { self.emitStatus() }
    }

    func detach(_ view: ARCaptureView) {
        guard host === view else { return }
        view.arView.session.pause()
        host = nil
        captureQueue.async {
            self.latestFrame = nil; self.depthAvailable = false
            self.beginSegment(reason: "native view detached")
            self.emitStatus()
        }
    }

    func updateViewport(_ size: CGSize, orientation: UIInterfaceOrientation) {
        captureQueue.async {
            if self.viewport != size || self.orientation != orientation {
                self.invalidateAprilTags()
                self.lastDepthPreviewTime = -.infinity
                DispatchQueue.main.async { [weak self] in self?.host?.depthView.image = nil }
            }
            self.viewport = size; self.orientation = orientation
        }
    }

    func startSession(name: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard self.recorder == nil && !self.finalizing else { completion(.failure(CaptureError.message("A recording is already active or finalizing."))); return }
            guard Self.lidarSupported, self.latestFrame?.sceneDepth != nil else { completion(.failure(CaptureError.message("Start requires live scene depth on a LiDAR-capable iPhone. Wait for tracking/depth."))); return }
            do {
                let recorder = try CaptureRecorder(name: name.isEmpty ? "Field capture" : name, debugSettings: self.debugSettings)
                self.recorder = recorder
                self.clearPoints()
                DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
                self.droppedFrames = 0; self.recordingStartedAt = Date(); self.lastError = nil
                self.counters = ["framesWritten": 0, "depthFrames": 0, "videoFrames": 0, "bytesWritten": 0]
                recorder.onProgress = { [weak self, weak recorder] values in
                    self?.captureQueue.async {
                        guard let self, self.recorder === recorder else { return }
                        self.counters = values
                        if let error = values["lastError"] as? String { self.lastError = error }
                        self.emitStatus()
                    }
                }
                recorder.event(["type": "segment", "segmentId": self.segment, "reason": "recording began", "timestamp": self.latestFrame?.timestamp ?? 0])
                recorder.event(["type": "debugSettingsAtStart", "settings": self.debugSettings.dictionary, "timestamp": self.latestFrame?.timestamp ?? 0])
                recorder.event(["type": "measurementsAtStart", "segmentId": self.segment, "timestamp": self.latestFrame?.timestamp ?? 0,
                    "measurements": self.spatialState.completed.map(\.dictionary), "floor": self.confirmedFloorDictionary() as Any? ?? NSNull()])
                self.emitStatus(); completion(.success(self.status()))
            } catch { self.lastError = error.localizedDescription; self.emitStatus(); completion(.failure(error)) }
        }
    }

    func stopSession(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard let recorder = self.recorder else { completion(.failure(CaptureError.message("No active recording."))); return }
            if self.tagInFlight, self.tagPendingRecorderID == recorder.id {
                recorder.event(["type": "aprilTagAnalysisPendingAtStop", "frameId": self.tagPendingFrameID as Any? ?? NSNull(), "timestamp": self.latestFrame?.timestamp ?? 0, "analysisSkippedFramesTotal": self.tagSkippedFrames, "policy": "late result is not appended after recording finalization"])
            }
            self.recorder = nil; self.finalizingRecorder = recorder; self.finalizing = true; self.emitStatus()
            recorder.finish(droppedFrames: self.droppedFrames) { result in
                self.captureQueue.async {
                    self.finalizing = false; self.finalizingRecorder = nil; self.recordingStartedAt = nil
                    DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false; self.endBackgroundTask() }
                    switch result {
                    case .success(let record):
                        self.counters["bytesWritten"] = record["sizeBytes"]
                        if let errors = record["errors"] as? [String], let error = errors.last { self.lastError = error }
                    case .failure(let error): self.lastError = error.localizedDescription
                    }
                    self.emitStatus(); completion(result)
                }
            }
        }
    }

    func getStatus(completion: @escaping ([String: Any]) -> Void) { captureQueue.async { completion(self.status()) } }

    func getDebugSettings(completion: @escaping ([String: Any]) -> Void) { captureQueue.async { completion(self.debugSettings.dictionary) } }

    func setDebugSettings(_ changes: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            do {
                let settings = try self.debugSettings.merging(changes)
                self.updateDebugSettings(settings, source: "manual", evidence: [:])
                completion(.success(settings.dictionary))
            } catch { completion(.failure(error)) }
        }
    }

    func applyMeasuredTagSize(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            do {
                guard self.spatialState.mode != .selectFloor, self.spatialState.floor != nil else { throw CaptureError.message("Finish floor setup with Done before measuring tag width.") }
                let distance = self.worldPoints.count == 2 ? Double(simd_length(self.worldPoints[1] - self.worldPoints[0])) : nil
                let age = self.latestFrame.map { ProcessInfo.processInfo.systemUptime - $0.timestamp } ?? .infinity
                let width = try TagDebugMath.measuredTagSize(points: self.points, worldDistance: distance, segmentID: self.segment, tracking: self.tracking, frameAgeSeconds: age)
                var settings = try self.debugSettings.merging(["tagSizeMeters": width])
                settings.tagSizeMode = "custom"
                settings.competitionYear = 0
                settings.tagSizeSource = "ar-two-point-edge"
                self.updateDebugSettings(settings, source: "ar-two-point-edge", evidence: ["sourcePoints": self.points, "measuredEdgeMeters": width, "method": "Euclidean distance of two live sceneDepth world endpoints; no PnP-derived size"])
                completion(.success(settings.dictionary))
            } catch { completion(.failure(error)) }
        }
    }

    private func updateDebugSettings(_ settings: TagDebugSettings, source: String, evidence: [String: Any]) {
        let old = debugSettings.dictionary
        let levelingChanged = debugSettings.levelFloorWithGravity != settings.levelFloorWithGravity
        let previousFloor = confirmedFloorDictionary()
        debugSettings = settings; settings.persist(); invalidateAprilTags()
        spatialState.setFloorLeveling(settings.levelFloorWithGravity)
        if levelingChanged {
            clearPoints()
            recorder?.event(["type": "floorReferenceChanged", "segmentId": segment, "timestamp": latestFrame?.timestamp ?? 0,
                "levelFloorWithGravity": settings.levelFloorWithGravity, "previousFloor": previousFloor as Any? ?? NSNull(),
                "floor": confirmedFloorDictionary() as Any? ?? NSNull(), "observedFloor": spatialState.observedFloor?.dictionary as Any? ?? NSNull()])
        }
        renderSpatial()
        var event: [String: Any] = ["type": "settingsChanged", "source": source, "settings": settings.dictionary, "previousSettings": old, "timestamp": latestFrame?.timestamp ?? 0, "segmentId": segment]
        for (key, value) in evidence { event[key] = value }
        recorder?.event(event)
        if source == "ar-two-point-edge", JSONSerialization.isValidJSONObject(evidence), let data = try? JSONSerialization.data(withJSONObject: evidence) { UserDefaults.standard.set(data, forKey: TagDebugSettings.tagSizeEvidenceKey) }
        emitStatus(force: true)
    }

    func setDebugMode(_ enabled: Bool, completion: @escaping ([String: Any]) -> Void) {
        captureQueue.async {
            self.debugMode = enabled
            if !enabled, self.spatialState.floor == nil, self.spatialState.mode != .selectFloor {
                self.spatialState.setMode(self.spatialState.requestedMode); self.clearPoints()
            }
            if enabled { self.previewMode = "camera" }
            self.prepareFloorSetupPresentation()
            self.invalidateAprilTags()
            self.renderSpatial()
            let preview = self.previewMode, hideTags = !enabled && self.spatialState.mode == .selectFloor
            DispatchQueue.main.async {
                self.host?.setDebugMode(enabled)
                self.host?.depthView.isHidden = preview == "camera"
                self.host?.tagOverlay.isHidden = preview != "camera" || hideTags
            }
            self.emitStatus(force: true); completion(self.status())
        }
    }

    func selectTag(_ id: Int) {
        captureQueue.async {
            guard self.latestTagDetections.contains(where: { ($0["id"] as? NSNumber)?.intValue == id }) else { return }
            self.selectedTagID = id; self.renderTagDebug(); self.emitStatus(force: true)
        }
    }

    func setPreviewMode(_ mode: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard ["camera", "depth", "confidence"].contains(mode) else { completion(.failure(CaptureError.message("Preview must be camera, depth, or confidence."))); return }
            let actual = self.spatialState.mode == .selectFloor ? "camera" : mode
            self.previewMode = actual; self.lastDepthPreviewTime = 0
            let hideTags = !self.debugMode && self.spatialState.mode == .selectFloor
            DispatchQueue.main.async {
                self.host?.depthView.isHidden = actual == "camera"
                self.host?.tagOverlay.isHidden = actual != "camera" || hideTags
            }
            self.emitStatus(); completion(.success(self.status()))
        }
    }

    func setDisplayZoom(_ factor: Double, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            do {
                self.displayZoom = try PreviewZoom.clamped(factor)
                let zoom = self.displayZoom
                DispatchQueue.main.async { [weak self] in self?.host?.setDisplayZoom(zoom) }
                // Reuse the current source pose and geometry; zoom is not a tracking reset.
                self.renderTagDebug()
                self.renderSpatial()
                self.emitStatus(); completion(.success(self.status()))
            } catch { completion(.failure(error)) }
        }
    }

    func clearMeasurements(completion: @escaping ([String: Any]) -> Void) {
        captureQueue.async {
            self.spatialState.clearMeasurements(); self.clearPoints(); self.lastError = nil
            self.recorder?.event(["type": "measurementsCleared", "segmentId": self.segment, "timestamp": self.latestFrame?.timestamp ?? 0, "floorRetained": self.spatialState.floor != nil])
            self.renderSpatial(); self.emitStatus(force: true); completion(self.status())
        }
    }

    func setSpatialMode(_ mode: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard let requested = SpatialMode(rawValue: mode) else { completion(.failure(CaptureError.message("Unknown measurement mode."))); return }
            self.spatialState.setMode(requested); self.clearPoints()
            self.prepareFloorSetupPresentation()
            if self.spatialState.mode == .selectFloor { self.invalidateAprilTags() }
            self.lastError = nil; self.renderSpatial(); self.emitStatus(force: true); completion(.success(self.status()))
        }
    }

    func setFloorVisible(_ visible: Bool, completion: @escaping ([String: Any]) -> Void) {
        captureQueue.async {
            self.showFloorPlanes = self.spatialState.mode == .selectFloor ? true : visible
            self.renderSpatial(); self.emitStatus(force: true); completion(self.status())
        }
    }

    func selectFloor(_ id: String) {
        captureQueue.async {
            do {
                guard self.showFloorPlanes, !self.debugMode, self.spatialState.mode == .selectFloor,
                      let frame = self.latestFrame else { throw CaptureError.message("Choose Set floor, then tap a visible horizontal surface.") }
                self.updateFloorCandidates(frame)
                guard let plane = self.floorCandidates.first(where: { $0.id == id }) else { throw CaptureError.message("That surface is no longer a current floor candidate.") }
                try self.spatialState.selectFloorCandidate(plane, tracking: self.tracking, frameAgeSeconds: self.frameAge(frame))
                self.clearPoints()
                self.recorder?.event(["type": "floorCandidateSelected", "segmentId": self.segment, "timestamp": frame.timestamp,
                    "frameId": self.frameID, "candidate": plane.dictionary, "floorSetup": self.floorSetupStatus()])
                self.lastError = nil; self.renderSpatial(); self.emitStatus(force: true)
            } catch { self.failMeasurement(error.localizedDescription) }
        }
    }

    func completeFloorSetup(_ expectedCandidateID: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            do {
                guard let frame = self.latestFrame else { throw CaptureError.message("Wait for live camera frames before finishing floor setup.") }
                self.updateFloorCandidates(frame)
                let setup = self.floorSetupStatus()
                let age = self.spatialState.candidate.map { ProcessInfo.processInfo.systemUptime-$0.timestamp } ?? .infinity
                try self.spatialState.completeFloorSetup(expectedCandidateID: expectedCandidateID, tracking: self.tracking, frameAgeSeconds: age)
                self.clearPoints(); self.invalidateAprilTags()
                self.recorder?.event(["type": "floorConfirmed", "segmentId": self.segment, "timestamp": frame.timestamp,
                    "frameId": self.frameID, "floor": self.confirmedFloorDictionary() as Any? ?? NSNull(), "floorSetup": setup,
                    "observedFloor": self.spatialState.observedFloor?.dictionary as Any? ?? NSNull(), "levelFloorWithGravity": self.spatialState.levelFloorWithGravity])
                let hideTags = self.previewMode != "camera"
                DispatchQueue.main.async { self.host?.tagOverlay.isHidden = hideTags }
                self.lastError = nil; self.renderSpatial(); self.emitStatus(force: true); completion(.success(self.status()))
            } catch { self.lastError = error.localizedDescription; self.emitStatus(force: true); completion(.failure(error)) }
        }
    }

    func resetTracking(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard self.recorder == nil, !self.finalizing, !self.resetting else { completion(.failure(CaptureError.message("Stop and finalize recording before resetting tracking."))); return }
            guard let session = self.session, let config = session.configuration else { completion(.failure(CaptureError.message("Live AR session is not available."))); return }
            self.resetting = true
            self.beginSegment(reason: "operator reset")
            self.latestFrame = nil; self.depthAvailable = false; self.tracking = "unavailable"; self.trackingReason = "resetting"
            DispatchQueue.main.async {
                session.run(config, options: [.resetTracking, .removeExistingAnchors])
                self.captureQueue.async {
                    self.minimumFrameTimestamp = ProcessInfo.processInfo.systemUptime
                    self.resetting = false
                    self.emitStatus(); completion(.success(self.status()))
                }
            }
            self.emitStatus()
        }
    }

    func addBookmark(note: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard let recorder = self.recorder, let frame = self.latestFrame else { completion(.failure(CaptureError.message("Start a recording before adding a bookmark."))); return }
            let bookmark: [String: Any] = ["id": UUID().uuidString, "type": "bookmark", "note": String(note.prefix(4000)), "timestamp": frame.timestamp, "frameId": self.frameID, "segmentId": self.segment]
            recorder.event(bookmark, frame: frame, frameID: self.frameID)
            completion(.success(bookmark))
        }
    }

    func listSessions(completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        captureQueue.async {
            do {
                guard FileManager.default.fileExists(atPath: CaptureRecorder.root.path) else { completion(.success([])); return }
                let folders = try FileManager.default.contentsOfDirectory(at: CaptureRecorder.root, includingPropertiesForKeys: nil)
                let records = folders.compactMap { folder -> [String: Any]? in
                    guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")), var value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
                    value["folderPath"] = folder.path
                    value["sizeBytes"] = CaptureRecorder.directorySize(folder)
                    value.merge(SavedRecordingStore.shared.descriptor(sessionID: folder.lastPathComponent)) { _, new in new }
                    return value
                }.sorted { ($0["createdAt"] as? String ?? "") > ($1["createdAt"] as? String ?? "") }
                completion(.success(records))
            } catch { completion(.failure(error)) }
        }
    }

    func exportSession(id: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard UUID(uuidString: id) != nil else { completion(.failure(CaptureError.message("Invalid session identifier."))); return }
            let folder = CaptureRecorder.root.appendingPathComponent(id, isDirectory: true)
            let manifest = folder.appendingPathComponent("manifest.json")
            do {
                let data = try Data(contentsOf: manifest)
                let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard value?["finalized"] as? Bool == true else { throw CaptureError.message("Stop and finalize this session before exporting.") }
                completion(.success(["sessionId": id, "folderPath": folder.path, "manifestPath": manifest.path, "finalized": true]))
            } catch { completion(.failure(error)) }
        }
    }

    func deleteSession(id: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        captureQueue.async {
            guard let identifier = UUID(uuidString: id) else { completion(.failure(CaptureError.message("Invalid session identifier."))); return }
            guard self.recorder.map({ UUID(uuidString: $0.id) != identifier }) ?? true,
                  self.finalizingRecorder.map({ UUID(uuidString: $0.id) != identifier }) ?? true else {
                completion(.failure(CaptureError.message("Stop and finish saving this recording before deleting it.")))
                return
            }
            // Recording IDs are newly generated at start and never reused, so
            // this checked ID cannot become active while disk cleanup runs.
            self.savedSessionQueue.async {
                do {
                    try SavedRecordingStore.shared.delete(sessionID: id)
                    completion(.success(["sessionId": id, "deleted": true]))
                } catch { completion(.failure(error)) }
            }
        }
    }

    func tap(_ point: CGPoint, in size: CGSize, orientation: UIInterfaceOrientation, displayZoom tapDisplayZoom: Double? = nil) {
        captureQueue.async {
            guard let frame = self.latestFrame, let depth = frame.sceneDepth else { self.failMeasurement("Scene depth is not available at this point."); return }
            guard case .normal = frame.camera.trackingState else { self.failMeasurement("Wait for normal AR tracking before selecting points."); return }
            guard self.spatialState.mode != .selectFloor, self.spatialState.floor != nil else { self.failMeasurement("Scan the floor and tap Done before measuring."); return }
            guard self.frameAge(frame) >= 0, self.frameAge(frame) <= 0.5 else { self.failMeasurement("Wait for a fresh camera frame before measuring."); return }
            let normalizedView = CGPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
            let baseDisplay = frame.displayTransform(for: orientation, viewportSize: size)
            let tapZoom = tapDisplayZoom ?? self.displayZoom
            let previewDisplay = PreviewZoom.displayTransform(base: baseDisplay, zoom: tapZoom)
            let normalizedImage = normalizedView.applying(baseDisplay.inverted())
            guard normalizedImage.x >= 0, normalizedImage.x < 1, normalizedImage.y >= 0, normalizedImage.y < 1 else { self.failMeasurement("Tap lies outside the captured image."); return }
            let pixelBuffer = depth.depthMap
            let x = min(CVPixelBufferGetWidth(pixelBuffer) - 1, Int(normalizedImage.x * Double(CVPixelBufferGetWidth(pixelBuffer))))
            let y = min(CVPixelBufferGetHeight(pixelBuffer) - 1, Int(normalizedImage.y * Double(CVPixelBufferGetHeight(pixelBuffer))))
            guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32,
                  CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { self.failMeasurement("Depth buffer is unavailable."); return }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly); self.failMeasurement("Depth buffer has no pixels."); return }
            let value = base.advanced(by: y * CVPixelBufferGetBytesPerRow(pixelBuffer)).assumingMemoryBound(to: Float.self)[x]
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            var confidenceLevel: Int?
            if let confidence = depth.confidenceMap, CVPixelBufferGetWidth(confidence) == CVPixelBufferGetWidth(pixelBuffer),
               CVPixelBufferGetHeight(confidence) == CVPixelBufferGetHeight(pixelBuffer), CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
               CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess {
                if let base = CVPixelBufferGetBaseAddress(confidence) { confidenceLevel = Int(base.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)[x]) }
                CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
            }
            guard value.isFinite, value > 0.05, value < 20, [1, 2].contains(confidenceLevel ?? -1) else { self.failMeasurement("Select valid depth with confidence 1 or 2. Try a nearby flat surface."); return }
            let k = frame.camera.intrinsics
            let resolution = frame.camera.imageResolution
            let u = Float(normalizedImage.x * resolution.width), v = Float(normalizedImage.y * resolution.height)
            let optical = SIMD4<Float>((u - k.columns.2.x) / k.columns.0.x * value, -(v - k.columns.2.y) / k.columns.1.y * value, -value, 1)
            let w = frame.camera.transform * optical
            let world = SIMD3<Float>(w.x, w.y, w.z)
            let record: [String: Any] = ["frameId": self.frameID, "timestamp": frame.timestamp, "segmentId": self.segment,
                "imagePixel": [Double(u), Double(v)], "viewNormalized": [normalizedView.x, normalizedView.y],
                "depthPixel": [x, y], "depthMeters": Double(value), "confidence": confidenceLevel as Any? ?? NSNull(),
                "worldMeters": Self.vector(world), "source": "sceneDepth", "displayZoom": tapZoom,
                "intrinsicsColumnMajor": Self.matrix(k), "cameraToWorldColumnMajor": Self.matrix(frame.camera.transform),
                "imageWidth": CVPixelBufferGetWidth(frame.capturedImage), "imageHeight": CVPixelBufferGetHeight(frame.capturedImage),
                "depthWidth": CVPixelBufferGetWidth(pixelBuffer), "depthHeight": CVPixelBufferGetHeight(pixelBuffer),
                "displayTransform": [baseDisplay.a, baseDisplay.b, baseDisplay.c, baseDisplay.d, baseDisplay.tx, baseDisplay.ty],
                "previewDisplayTransform": [previewDisplay.a, previewDisplay.b, previewDisplay.c, previewDisplay.d, previewDisplay.tx, previewDisplay.ty],
                "interfaceOrientation": orientation.rawValue, "viewportWidth": size.width, "viewportHeight": size.height]
            let completed: SpatialMeasurement?
            do { completed = try self.spatialState.append(SpatialPoint(world: world, record: record), tracking: self.tracking, frameAgeSeconds: self.frameAge(frame)) }
            catch { self.failMeasurement(error.localizedDescription); return }
            self.points = self.spatialState.pending.map(\.record); self.worldPoints = self.spatialState.pending.map(\.world)
            self.lastMeasurement = ["pointCount": self.points.count, "distanceMeters": NSNull(), "verticalMeters": NSNull(), "points": self.points, "source": "sceneDepth", "recorded": self.recorder != nil, "kind": self.spatialState.mode == .height ? "height" : "distance"]
            if self.worldPoints.count == 2 {
                let delta = self.worldPoints[1] - self.worldPoints[0]
                self.lastMeasurement["distanceMeters"] = Double(simd_length(delta))
                self.lastMeasurement["verticalMeters"] = Double(delta.y)
                self.lastMeasurement["horizontalMeters"] = Double(simd_length(SIMD2<Float>(delta.x, delta.z)))
                self.lastMeasurement["label"] = "3D endpoint distance and signed vertical difference; not validated survey height"
            }
            if let completed {
                self.lastMeasurement.merge(completed.dictionary) { _, new in new }
                self.lastMeasurement["pointCount"] = 2
                self.lastMeasurement["points"] = completed.sourcePoints
                self.lastMeasurement["source"] = completed.kind == "height" ? "ARPlaneAnchor+sceneDepth" : "sceneDepth"
                self.recorder?.event(["type": "measurementCompleted", "segmentId": self.segment, "frameId": self.frameID, "timestamp": frame.timestamp, "measurement": completed.dictionary])
            }
            self.lastError = nil
            var event = self.lastMeasurement
            event["type"] = "measurementPoint"; event["timestamp"] = frame.timestamp; event["frameId"] = self.frameID; event["segmentId"] = self.segment
            self.recorder?.event(event, frame: frame, frameID: self.frameID)
            self.renderSpatial()
            self.emitStatus()
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !resetting, frame.timestamp >= minimumFrameTimestamp else { return }
        latestFrame = frame; frameCounter += 1; depthAvailable = frame.sceneDepth != nil
        let trackingInfo = Self.trackingInfo(frame.camera.trackingState)
        tracking = trackingInfo.0; trackingReason = trackingInfo.1
        let trackingKey = tracking + trackingReason
        if trackingKey != lastTrackingKey {
            if tracking != "normal" { clearPoints(); invalidateAprilTags(); clearFloorFitCache() }
            recorder?.event(["type": "trackingChanged", "tracking": tracking, "reason": trackingReason, "frameId": frameID, "timestamp": frame.timestamp, "segmentId": segment])
            lastTrackingKey = trackingKey
        }
        updateFloorCandidates(frame)
        renderSpatial(frame)
        analyzeAprilTags(frame)
        if let recorder {
            var metadata: [String: Any] = ["frameId": frameID, "segmentId": segment, "timestamp": frame.timestamp,
                "imageWidth": CVPixelBufferGetWidth(frame.capturedImage), "imageHeight": CVPixelBufferGetHeight(frame.capturedImage),
                "pixelFormat": CVPixelBufferGetPixelFormatType(frame.capturedImage), "intrinsicsColumnMajor": Self.matrix(frame.camera.intrinsics),
                "cameraToWorldColumnMajor": Self.matrix(frame.camera.transform), "tracking": tracking, "trackingReason": trackingReason,
                "worldMappingStatus": frame.worldMappingStatus.rawValue, "interfaceOrientation": orientation.rawValue,
                "viewportWidth": viewport.width, "viewportHeight": viewport.height, "depthAvailable": depthAvailable,
                "droppedWriterFramesTotal": droppedFrames, "exposureDurationSeconds": frame.camera.exposureDuration]
            let display = frame.displayTransform(for: orientation, viewportSize: viewport)
            metadata["displayTransform"] = [display.a, display.b, display.c, display.d, display.tx, display.ty]
            let previewDisplay = PreviewZoom.displayTransform(base: display, zoom: displayZoom)
            metadata["displayZoom"] = displayZoom
            metadata["previewDisplayTransform"] = [previewDisplay.a, previewDisplay.b, previewDisplay.c, previewDisplay.d, previewDisplay.tx, previewDisplay.ty]
            if frame.timestamp - lastGeometryTime >= 1 {
                lastGeometryTime = frame.timestamp
                metadata["planes"] = frame.anchors.compactMap { anchor -> [String: Any]? in
                    guard let plane = anchor as? ARPlaneAnchor else { return nil }
                    return ["id": plane.identifier.uuidString, "alignment": plane.alignment.rawValue, "center": Self.vector(plane.center), "extent": Self.vector(plane.extent), "transformColumnMajor": Self.matrix(plane.transform)]
                }
                if let features = frame.rawFeaturePoints {
                    metadata["featurePointsSample"] = features.points.prefix(200).map(Self.vector)
                    metadata["featurePointsTotal"] = features.points.count
                }
                if let available = try? CaptureRecorder.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, available < 250_000_000 {
                    lastError = "Recording stopped: less than 250 MB free storage."
                    stopSession { _ in }; emitStatus(); return
                }
            }
            if !recorder.append(frame: frame, metadata: metadata) { droppedFrames += 1 }
        }
        if previewMode != "camera", frame.timestamp - lastDepthPreviewTime > 0.2 {
            lastDepthPreviewTime = frame.timestamp
            let display = frame.displayTransform(for: orientation, viewportSize: viewport)
            let image = Self.depthImage(frame: frame, mode: previewMode, displayTransform: display)
            DispatchQueue.main.async { [weak self] in self?.host?.depthView.image = image }
        }
        if frame.timestamp - lastStatusTime > 0.25 { lastStatusTime = frame.timestamp; emitStatus() }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        captureQueue.async { self.beginSegment(reason: "AR session interrupted"); self.tracking = "unavailable"; self.emitStatus() }
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        captureQueue.async { self.beginSegment(reason: "AR interruption ended"); self.emitStatus() }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        captureQueue.async { self.lastError = error.localizedDescription; self.beginSegment(reason: "AR error"); self.emitStatus() }
    }

    private var frameID: String { String(format: "f%010d", frameCounter) }
    private func endBackgroundTask() {
        dispatchPrecondition(condition: .onQueue(.main))
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    private func beginSegment(reason: String) {
        let oldSegment = segment, count = spatialState.completed.count, oldTimestamp = latestFrame?.timestamp ?? 0
        segment = UUID().uuidString; spatialState.reset(segmentID: segment); floorCandidates = []; clearPoints(); invalidateAprilTags()
        clearFloorFitCache()
        minimumFrameTimestamp = max(minimumFrameTimestamp, ProcessInfo.processInfo.systemUptime)
        latestFrame = nil; depthAvailable = false; tracking = "unavailable"; trackingReason = reason; lastTrackingKey = ""
        prepareFloorSetupPresentation(refreshCandidates: false)
        spatialRenderLock.lock(); spatialRenderGeneration += 1; spatialRenderLock.unlock()
        renderSpatial(clear: true)
        recorder?.event(["type": "measurementsInvalidated", "segmentId": oldSegment, "newSegmentId": segment, "reason": reason, "measurementCount": count, "timestamp": oldTimestamp])
        recorder?.event(["type": "segment", "segmentId": segment, "reason": reason, "timestamp": oldTimestamp])
    }
    private func clearPoints() {
        spatialState.clearPending()
        points = []; worldPoints = []
        lastMeasurement = ["pointCount": 0, "distanceMeters": NSNull(), "verticalMeters": NSNull()]
    }
    private func frameAge(_ frame: ARFrame) -> Double { ProcessInfo.processInfo.systemUptime - frame.timestamp }
    private func confirmedFloorDictionary() -> [String: Any]? {
        guard spatialState.mode != .selectFloor else { return nil }
        guard var value = spatialState.floor?.dictionary else { return nil }
        value["operatorConfirmed"] = true
        return value
    }
    private func floorSetupStatus() -> [String: Any] {
        let age = spatialState.candidate.map { ProcessInfo.processInfo.systemUptime-$0.timestamp } ?? .infinity
        return spatialState.floorSetupStatus(tracking: tracking, frameAgeSeconds: age)
    }
    private func prepareFloorSetupPresentation(refreshCandidates: Bool = true) {
        guard spatialState.mode == .selectFloor else { return }
        showFloorPlanes = true; previewMode = "camera"
        if refreshCandidates, let frame = latestFrame { updateFloorCandidates(frame) }
        let hideTags = !debugMode
        DispatchQueue.main.async {
            self.host?.depthView.isHidden = true
            self.host?.tagOverlay.isHidden = hideTags
            if hideTags { self.host?.clearAprilTagOverlay() }
        }
    }
    private func updateFloorCandidates(_ frame: ARFrame) {
        let pendingID = spatialState.candidate?.id
        var candidates = frame.anchors.compactMap { anchor -> SpatialPlane? in
            guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal else { return nil }
            let classification: String
            switch plane.classification {
            case .floor: classification = "floor"
            case .none: classification = "unclassified"
            default: return nil // Tables, seats, ceilings, and other classified surfaces are not floor choices.
            }
            let transform = plane.transform
            func world(_ local: SIMD3<Float>) -> SIMD3<Float> {
                let p = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                return SIMD3<Float>(p.x, p.y, p.z)
            }
            let n = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            guard SpatialMeasurementMath.finite(n), simd_length(n) > 0 else { return nil }
            let normal = simd_normalize(n), origin = world(plane.center)
            guard abs(normal.y) >= 0.8, SpatialMeasurementMath.finite(origin) else { return nil }
            let boundary = plane.geometry.boundaryVertices
            var vertices: [SIMD3<Float>]
            if boundary.count >= 3 {
                let count = min(64, boundary.count)
                vertices = (0..<count).map { world(boundary[$0 * boundary.count / count]) }
            } else {
                let c = plane.center, x = plane.extent.x / 2, z = plane.extent.z / 2
                vertices = [SIMD3<Float>(c.x-x,c.y,c.z-z), SIMD3<Float>(c.x+x,c.y,c.z-z),
                    SIMD3<Float>(c.x+x,c.y,c.z+z), SIMD3<Float>(c.x-x,c.y,c.z+z)].map(world)
            }
            guard vertices.allSatisfy(SpatialMeasurementMath.finite) else { return nil }
            return SpatialPlane(id: plane.identifier.uuidString, classification: classification, origin: origin, normal: normal,
                vertices: vertices, segmentID: segment, frameID: frameID, timestamp: frame.timestamp)
        }
        if let pendingID, let index = candidates.firstIndex(where: { $0.id == pendingID }) {
            candidates.insert(candidates.remove(at: index), at: 0)
        }
        floorCandidates = Array(candidates.prefix(24))
        spatialState.updateCandidates(floorCandidates)
        refinePendingFloor(frame)
    }
    private func clearFloorFitCache() {
        cachedFloorFit = nil; fittingCandidateID = nil; lastFloorFitAttempt = -.infinity
    }
    private func refinePendingFloor(_ frame: ARFrame) {
        guard spatialState.mode == .selectFloor, let candidate = spatialState.candidate, tracking == "normal",
              frameAge(frame) >= 0, frameAge(frame) <= 0.5 else { clearFloorFitCache(); return }
        if fittingCandidateID != candidate.id { clearFloorFitCache(); fittingCandidateID = candidate.id }
        if frame.timestamp-lastFloorFitAttempt >= 0.25 {
            lastFloorFitAttempt = frame.timestamp
            let samples = FloorDepthSampler.samples(frame: frame, plane: candidate, maximumCount: 512)
            if let fit = FloorPlaneFit.fit(points: samples, referenceXZ: SIMD2<Float>(candidate.origin.x, candidate.origin.z)) {
                cachedFloorFit = CachedFloorFit(segmentID: segment, planeID: candidate.id, frameID: frameID, timestamp: frame.timestamp, fit: fit)
            }
        }
        guard let cached = cachedFloorFit, cached.segmentID == segment, cached.planeID == candidate.id,
              frame.timestamp-cached.timestamp >= 0, frame.timestamp-cached.timestamp <= 0.75,
              let index = floorCandidates.firstIndex(where: { $0.id == candidate.id }) else { cachedFloorFit = nil; return }
        let fit = cached.fit
        let vertices = candidate.vertices.map { point -> SIMD3<Float> in
            let y = fit.origin.y - (fit.normal.x*(point.x-fit.origin.x)+fit.normal.z*(point.z-fit.origin.z))/fit.normal.y
            return SIMD3<Float>(point.x, y, point.z)
        }
        guard vertices.allSatisfy(SpatialMeasurementMath.finite) else { return }
        let metadata: [String: Any] = ["sampleCount": fit.sampleCount, "inlierCount": fit.inlierCount, "rmsMeters": fit.rmsMeters,
            "frameId": cached.frameID, "timestamp": cached.timestamp]
        floorCandidates[index] = SpatialPlane(id: candidate.id, classification: candidate.classification, origin: fit.origin,
            normal: fit.normal, vertices: vertices, segmentID: segment, frameID: candidate.frameID, timestamp: candidate.timestamp,
            tiltSource: "sceneDepth-plane-fit", floorFit: metadata)
        spatialState.updateCandidates(floorCandidates)
    }
    /// One pending main-queue delivery slot: newer frames replace geometry waiting to be displayed.
    private func renderSpatial(_ sourceFrame: ARFrame? = nil, clear: Bool = false) {
        let frame = sourceFrame ?? latestFrame
        let setupActive = spatialState.mode == .selectFloor
        var planes = !debugMode && showFloorPlanes && !clear ? floorCandidates : []
        if !setupActive && (!planes.isEmpty || (!debugMode && showFloorPlanes && !clear)) {
            if let confirmed = spatialState.floor {
                // Use the frozen datum actually used by height measurements, not later plane refinement.
                planes.removeAll { $0.id == confirmed.id }; planes.insert(confirmed, at: 0)
                planes = Array(planes.prefix(24))
            }
        }
        let base = frame?.displayTransform(for: orientation, viewportSize: viewport) ?? .identity
        spatialRenderLock.lock()
        let snapshot = SpatialRenderSnapshot(generation: spatialRenderGeneration, mode: spatialState.mode,
            visible: !clear && spatialState.mode != .tagWidth, planes: planes,
            measurements: clear || setupActive ? [] : spatialState.completed,
            pendingPoints: clear || setupActive || spatialState.pending.count != 1 ? [] : spatialState.pending.map(\.world),
            automaticTagHeights: clear ? [] : TagHeightVectors.make(from: latestTagDetections, floor: spatialState.floor,
                segmentID: segment, frameID: tagResultFrameID, tracking: tracking, mode: spatialState.mode, now: ProcessInfo.processInfo.systemUptime),
            selectedFloorID: setupActive ? nil : spatialState.floor?.id,
            pendingSelectedFloorID: setupActive ? spatialState.candidate?.id : nil, isTrackingNormal: !clear && tracking == "normal",
            cameraToWorld: frame?.camera.transform ?? matrix_identity_float4x4,
            intrinsics: frame?.camera.intrinsics ?? matrix_identity_float3x3,
            imageSize: frame?.camera.imageResolution ?? CGSize(width: 1, height: 1),
            displayTransform: PreviewZoom.displayTransform(base: base, zoom: displayZoom), timestamp: frame?.timestamp ?? 0,
            showImperialHeight: debugSettings.showImperialHeight)
        pendingSpatialRender = snapshot
        guard !spatialRenderScheduled else { spatialRenderLock.unlock(); return }
        spatialRenderScheduled = true
        spatialRenderLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.spatialRenderLock.lock()
            let newest = self.pendingSpatialRender, generation = self.spatialRenderGeneration
            self.pendingSpatialRender = nil; self.spatialRenderScheduled = false
            self.spatialRenderLock.unlock()
            guard let newest, newest.generation == generation else { return }
            self.host?.applySpatial(newest)
        }
    }
    private func failMeasurement(_ error: String) { lastError = error; emitStatus() }
    private func status() -> [String: Any] {
        expireAprilTagsIfNeeded()
        var value = counters
        value["recording"] = recorder != nil; value["finalizing"] = finalizing
        value["sessionId"] = recorder?.id as Any? ?? NSNull(); value["name"] = recorder?.name as Any? ?? NSNull()
        value["folderPath"] = recorder?.folder.path as Any? ?? NSNull()
        value["tracking"] = tracking; value["trackingReason"] = trackingReason
        value["lidarAvailable"] = Self.lidarSupported; value["depthAvailable"] = depthAvailable
        value["elapsedSeconds"] = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        value["droppedFrames"] = droppedFrames; value["lastError"] = lastError as Any? ?? NSNull()
        value["measurement"] = lastMeasurement; value["previewMode"] = previewMode; value["segmentId"] = segment
        value["displayZoom"] = displayZoom
        value["debugMode"] = debugMode
        let available = tracking == "normal" && latestFrame.map({ frameAge($0) <= 0.5 && frameAge($0) >= 0 }) == true
        let floorUsable = spatialState.mode != .selectFloor && spatialState.floor != nil
        let observed = spatialState.mode == .selectFloor ? spatialState.candidate : spatialState.observedFloor
        value["spatial"] = ["mode": spatialState.mode.rawValue, "showFloorPlanes": showFloorPlanes,
            "floorSelected": floorUsable, "floorId": floorUsable ? spatialState.floor!.id as Any : NSNull(),
            "floorClassification": floorUsable ? spatialState.floor!.classification as Any : NSNull(), "measurementCount": spatialState.completed.count,
            "pendingCount": spatialState.pending.count, "candidateCount": floorCandidates.count, "available": available && floorUsable, "valid": available && floorUsable,
            "floorSetup": floorSetupStatus(),
            "floorTiltDegrees": observed?.observedTiltDegrees as Any? ?? NSNull(), "tiltSource": observed?.tiltSource ?? "unavailable",
            "levelFloorWithGravity": spatialState.levelFloorWithGravity,
            "effectiveFloorTiltDegrees": floorUsable ? (spatialState.floor?.effectiveTiltDegrees as Any? ?? NSNull()) : NSNull(),
            "lastMeasurement": spatialState.completed.last?.dictionary as Any? ?? NSNull()]
        var selectedDebug = selectedTagDebug()
        if let timestamp = lastTagResultTimestamp { selectedDebug?["ageSeconds"] = max(0, ProcessInfo.processInfo.systemUptime - timestamp) }
        value["aprilTag"] = ["state": tagState, "family": "tag36h11", "ids": tagIDs, "count": tagIDs.count,
            "latencyMilliseconds": tagLatencyMilliseconds as Any? ?? NSNull(), "analyzedFrames": tagAnalyzedFrames,
            "skippedFrames": tagSkippedFrames, "lateRecordingResults": tagLateRecordingResults,
            "timestamp": lastTagResultTimestamp as Any? ?? NSNull(), "frameId": tagResultFrameID as Any? ?? NSNull(),
            "error": tagError as Any? ?? NSNull(), "debugSettings": debugSettings.dictionary,
            "selectedId": selectedTagID as Any? ?? NSNull(), "selectedDebug": selectedDebug as Any? ?? NSNull(), "analysisHz": analysisHz]
        return value
    }
    private func invalidateAprilTags() {
        tagGeneration += 1; tagIDs = []; latestTagDetections = []; latestTagIntrinsics = nil; lastTagResultTimestamp = nil; tagResultFrameID = nil
        tagState = "waiting"
        DispatchQueue.main.async { [weak self] in self?.host?.clearAprilTagOverlay() }
    }
    private func expireAprilTagsIfNeeded() {
        guard let timestamp = lastTagResultTimestamp, ProcessInfo.processInfo.systemUptime - timestamp > 0.4 else { return }
        if !tagIDs.isEmpty || tagResultFrameID != nil {
            tagIDs = []; latestTagDetections = []; tagResultFrameID = nil
            if tagError == nil { tagState = "waiting" }
            DispatchQueue.main.async { [weak self] in self?.host?.clearAprilTagOverlay() }
        }
    }
    private func analyzeAprilTags(_ frame: ARFrame) {
        guard !tagInFlight else { tagSkippedFrames += 1; return }
        tagInFlight = true; tagState = "running"
        let sourceFrameID = frameID, sourceSegmentID = segment, sourceRecorderID = recorder?.id
        tagPendingFrameID = sourceFrameID; tagPendingRecorderID = sourceRecorderID
        let generation = tagGeneration, timestamp = frame.timestamp
        let buffer = frame.capturedImage
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let settings = debugSettings, sourceTracking = tracking
        let k = frame.camera.intrinsics
        let sourceFloor = spatialState.mode == .selectFloor ? nil : spatialState.floor
        let sourceCameraToWorld = frame.camera.transform
        let poseIntrinsics = [Double(k.columns.0.x), Double(k.columns.1.y), Double(k.columns.2.x), Double(k.columns.2.y)]
        let depthBuffer = frame.sceneDepth?.depthMap, confidenceBuffer = frame.sceneDepth?.confidenceMap
        let display = frame.displayTransform(for: orientation, viewportSize: viewport)
        let previewDisplay = PreviewZoom.displayTransform(base: display, zoom: displayZoom)
        let sourceMetadata: [String: Any] = ["type": "aprilTagDetections", "frameId": sourceFrameID,
            "segmentId": sourceSegmentID, "timestamp": timestamp, "family": "tag36h11",
            "imageWidth": width, "imageHeight": height, "pixelFormat": CVPixelBufferGetPixelFormatType(buffer),
            "intrinsicsColumnMajor": Self.matrix(frame.camera.intrinsics), "cameraToWorldColumnMajor": Self.matrix(frame.camera.transform),
            "displayTransform": [display.a, display.b, display.c, display.d, display.tx, display.ty],
            "displayZoom": displayZoom, "previewDisplayTransform": [previewDisplay.a, previewDisplay.b, previewDisplay.c, previewDisplay.d, previewDisplay.tx, previewDisplay.ty],
            "viewportWidth": viewport.width, "viewportHeight": viewport.height, "interfaceOrientation": orientation.rawValue,
            "tracking": tracking, "trackingReason": trackingReason,
            "analysisSkippedFramesTotal": tagSkippedFrames, "targetAnalysisHz": 30, "maxAnalysisInFlight": 1,
            "recordingId": sourceRecorderID as Any? ?? NSNull(), "poseEstimation": true, "debugSettings": settings.dictionary,
            "calculationCore": SpatialCoreInfo.dictionary,
            "floorSnapshot": sourceFloor.map { floor -> [String: Any] in
                var record = floor.dictionary; record["operatorConfirmed"] = true; return record
            } as Any? ?? NSNull()]
        tagQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                if self.tagDetector == nil { self.tagDetector = AFTagDetector() }
                let started = ProcessInfo.processInfo.systemUptime
                let result = self.tagDetector?.detectPixelBuffer(buffer, intrinsics: poseIntrinsics.map(NSNumber.init(value:)), tagSizeMeters: settings.tagSizeMeters) as? [[String: Any]]
                let error = result == nil ? (self.tagDetector?.lastError?.localizedDescription ?? "AprilTag detector returned no result") : nil
                let detections = (result ?? []).map { detection -> [String: Any] in
                    let center = TagDebugMath.numbers(detection["center"], count: 2) ?? []
                    let depth = TagDebugMath.sampleDepth(depth: depthBuffer, confidence: confidenceBuffer, center: center, imageWidth: width, imageHeight: height)
                    let sized = TagDebugMath.resolveTagSize(detection, depth: depth, settings: settings, tracking: sourceTracking)
                    let enriched = TagDebugMath.enrich(sized, depth: depth, settings: settings, tracking: sourceTracking)
                    let ranged = TagCameraRanges.enrich(enriched, context: TagCameraRangesContext(intrinsics: k,
                        frameID: sourceFrameID, segmentID: sourceSegmentID, timestamp: timestamp))
                    let oriented = TagGravityOrientation.enrich(ranged, context: TagGravityOrientationContext(
                        cameraToWorld: sourceCameraToWorld, settings: settings, tracking: sourceTracking,
                        frameID: sourceFrameID, segmentID: sourceSegmentID, timestamp: timestamp,
                        frameAgeSeconds: ProcessInfo.processInfo.systemUptime-timestamp))
                    return TagFloorHeight.enrich(oriented, context: TagFloorHeightContext(floor: sourceFloor,
                        cameraToWorld: sourceCameraToWorld, intrinsics: k, settings: settings, tracking: sourceTracking,
                        frameID: sourceFrameID, segmentID: sourceSegmentID, timestamp: timestamp,
                        frameAgeSeconds: ProcessInfo.processInfo.systemUptime-timestamp))
                }
                let completed = ProcessInfo.processInfo.systemUptime
                let latency = (completed - started) * 1000
                self.captureQueue.async {
                    self.tagInFlight = false; self.tagPendingFrameID = nil; self.tagPendingRecorderID = nil
                    if result != nil {
                        self.tagAnalyzedFrames += 1
                        self.tagCompletionTimes.append(completed)
                        self.tagCompletionTimes.removeAll { $0 < completed - 2 }
                    }
                    let selected = self.chooseSelectedTag(detections, imageSize: CGSize(width: width, height: height))
                    var event = sourceMetadata
                    event["detections"] = detections; event["latencyMilliseconds"] = latency
                    event["analysisSucceeded"] = result != nil; event["detectorError"] = error as Any? ?? NSNull()
                    event["selectedId"] = selected as Any? ?? NSNull()
                    event["selectedDebug"] = detections.first(where: { ($0["id"] as? NSNumber)?.intValue == selected })?["debug"] as Any? ?? NSNull()
                    if let sourceRecorderID {
                        if let recorder = self.recorder, recorder.id == sourceRecorderID {
                            recorder.aprilTagEvent(event, pixelBuffer: detections.isEmpty ? nil : buffer, frameID: sourceFrameID)
                        } else { self.tagLateRecordingResults += 1 }
                    }
                    guard generation == self.tagGeneration, sourceSegmentID == self.segment else { self.emitStatus(); return }
                    self.tagLatencyMilliseconds = latency; self.tagError = error
                    self.lastTagResultTimestamp = timestamp; self.tagResultFrameID = sourceFrameID
                    self.latestTagDetections = detections; self.selectedTagID = selected
                    self.latestTagImageSize = CGSize(width: width, height: height); self.latestTagDisplayTransform = display
                    self.latestTagIntrinsics = poseIntrinsics
                    let age = ProcessInfo.processInfo.systemUptime - timestamp
                    self.tagIDs = age <= 0.4 ? Array(Set(detections.compactMap { ($0["id"] as? NSNumber)?.intValue })).sorted() : []
                    self.tagState = error == nil ? (age <= 0.4 ? "ready" : "waiting") : "error"
                    if age <= 0.4 && error == nil { self.renderTagDebug() }
                    else { DispatchQueue.main.async { [weak self] in self?.host?.clearAprilTagOverlay() } }
                    self.renderSpatial()
                    self.captureQueue.asyncAfter(deadline: .now() + max(0, 0.4 - age)) { [weak self] in
                        guard let self, self.tagResultFrameID == sourceFrameID else { return }
                        self.expireAprilTagsIfNeeded(); self.emitStatus()
                    }
                    self.emitStatus()
                }
            }
        }
    }
    private var analysisHz: Double {
        guard tagCompletionTimes.count > 1, let first = tagCompletionTimes.first, let last = tagCompletionTimes.last, last > first,
              ProcessInfo.processInfo.systemUptime - last < 0.5 else { return 0 }
        return Double(tagCompletionTimes.count - 1) / (last - first)
    }
    private func chooseSelectedTag(_ rows: [[String: Any]], imageSize: CGSize) -> Int? {
        if let id = selectedTagID, rows.contains(where: { ($0["id"] as? NSNumber)?.intValue == id }) { return id }
        return rows.min { a, b in
            func distance(_ row: [String: Any]) -> Double {
                guard let center = TagDebugMath.numbers(row["center"], count: 2), imageSize.width > 0, imageSize.height > 0 else { return .infinity }
                return pow(center[0] / imageSize.width - 0.5, 2) + pow(center[1] / imageSize.height - 0.5, 2)
            }
            return distance(a) < distance(b)
        }.flatMap { ($0["id"] as? NSNumber)?.intValue }
    }
    private func selectedTagDebug() -> [String: Any]? {
        latestTagDetections.first(where: { ($0["id"] as? NSNumber)?.intValue == selectedTagID })?["debug"] as? [String: Any]
    }
    private func renderTagDebug() {
        guard debugMode || spatialState.mode != .selectFloor else {
            DispatchQueue.main.async { [weak self] in self?.host?.clearAprilTagOverlay() }; return
        }
        guard let frameID = tagResultFrameID, let timestamp = lastTagResultTimestamp, ProcessInfo.processInfo.systemUptime - timestamp <= 0.4 else {
            DispatchQueue.main.async { [weak self] in self?.host?.clearAprilTagOverlay() }; return
        }
        let rows = latestTagDetections, selected = selectedTagID, debug = selectedTagDebug(), size = latestTagImageSize
        let display = PreviewZoom.displayTransform(base: latestTagDisplayTransform, zoom: displayZoom)
        let settings = debugSettings, hz = analysisHz, latency = tagLatencyMilliseconds
        let intrinsics = latestTagIntrinsics
        DispatchQueue.main.async { [weak self] in
            self?.host?.showAprilTagOverlay(rows, imageSize: size, displayTransform: display, frameID: frameID, expiresAt: timestamp+0.4, selectedID: selected, showPoseAxes: settings.showPoseAxes, intrinsics: intrinsics, showImperialHeight: settings.showImperialHeight, distanceDeltaThresholdMeters: settings.distanceDeltaThresholdMeters)
            self?.host?.debugPanel.show(debug: debug, frameID: frameID, timestamp: timestamp, analysisHz: hz, latencyMilliseconds: latency, settings: settings)
        }
    }
    private func emitStatus(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastJSEmissionTime >= 0.2 else { return }
        lastJSEmissionTime = now
        let value = status()
        DispatchQueue.main.async { [weak self] in
            self?.host?.updateLabel(value)
            self?.onStatus?(value)
        }
    }
    static func vector(_ v: SIMD3<Float>) -> [Double] { [Double(v.x), Double(v.y), Double(v.z)] }
    static func matrix(_ m: simd_float4x4) -> [Double] { (0..<4).flatMap { c in (0..<4).map { r in Double(m[c][r]) } } }
    static func matrix(_ m: simd_float3x3) -> [Double] { (0..<3).flatMap { c in (0..<3).map { r in Double(m[c][r]) } } }
    static func trackingInfo(_ state: ARCamera.TrackingState) -> (String, String) {
        switch state {
        case .normal: return ("normal", "")
        case .notAvailable: return ("unavailable", "notAvailable")
        case .limited(let reason):
            switch reason {
            case .initializing: return ("limited", "initializing")
            case .excessiveMotion: return ("limited", "excessiveMotion")
            case .insufficientFeatures: return ("limited", "insufficientFeatures")
            case .relocalizing: return ("limited", "relocalizing")
            @unknown default: return ("limited", "unknown")
            }
        }
    }
    private static func depthImage(frame: ARFrame, mode: String, displayTransform: CGAffineTransform) -> UIImage? {
        guard let depth = frame.sceneDepth,
              let imageOrientation = PreviewZoom.imageOrientation(for: displayTransform) else { return nil }
        let buffer = mode == "confidence" ? depth.confidenceMap : depth.depthMap
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let offset = (y * width + x) * 4
            if mode == "confidence" {
                let c = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)[x]
                pixels[offset] = c == 2 ? 25 : 240; pixels[offset+1] = c == 0 ? 30 : 220; pixels[offset+2] = 40
            } else {
                let z = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)[x]
                if z.isFinite && z > 0 {
                    let t = max(0, min(1, z / 6))
                    pixels[offset] = UInt8(255 * (1-t)); pixels[offset+1] = UInt8(200 * (1-abs(t*2-1))); pixels[offset+2] = UInt8(255*t)
                }
            }
            pixels[offset+3] = 255
        } }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: imageOrientation)
    }
}

final class ARCaptureView: UIView, UIGestureRecognizerDelegate {
    private let previewContainer = UIView()
    let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    let depthView = UIImageView()
    let tagOverlay = AprilTagOverlayView(frame: .zero)
    let spatialOverlay = SpatialMeasurementOverlayView(frame: .zero)
    let debugPanel = TagDebugPanelView(frame: .zero)
    private var debugEnabled = true
    private let statusLabel = UILabel()
    private var attached = false
    private(set) var displayZoom = PreviewZoom.minimum
    private var pinchStartZoom = PreviewZoom.minimum
    private var spatialMode = SpatialMode.distance
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewContainer.clipsToBounds = true
        addSubview(previewContainer); previewContainer.addSubview(arView)
        depthView.contentMode = .scaleAspectFill; depthView.clipsToBounds = true; depthView.alpha = 0.88; depthView.isHidden = true
        previewContainer.addSubview(depthView)
        addSubview(spatialOverlay)
        addSubview(tagOverlay)
        addSubview(debugPanel)
        debugPanel.onPreferredHeightChanged = { [weak self] _ in
            self?.setNeedsLayout()
            self?.layoutIfNeeded()
        }
        statusLabel.textColor = .white; statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        statusLabel.numberOfLines = 3; statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        statusLabel.text = "Starting ARKit · tap two surfaces to measure"
        statusLabel.isHidden = true // React Native supplies the visible status overlay.
        addSubview(statusLabel)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        tap.require(toFail: pinch)
        addGestureRecognizer(pinch)
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && !attached { attached = true; ARCaptureCoordinator.shared.attach(self) }
        else if window == nil && attached { attached = false; ARCaptureCoordinator.shared.detach(self) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Camera and overlays share the current viewport; zoom only adds a centered display scale.
        previewContainer.frame = bounds
        for view in [arView as UIView, depthView] {
            view.bounds = CGRect(origin: .zero, size: previewContainer.bounds.size)
            view.center = CGPoint(x: previewContainer.bounds.midX, y: previewContainer.bounds.midY)
        }
        applyDisplayZoom()
        tagOverlay.frame = bounds
        spatialOverlay.frame = bounds
        statusLabel.frame = CGRect(x: 10, y: 10, width: max(0, bounds.width-20), height: 58)
        debugPanel.frame = TagDebugPanelView.overlayFrame(in: bounds, preferredHeight: debugPanel.preferredHeight)
        ARCaptureCoordinator.shared.updateViewport(arView.bounds.size, orientation: window?.windowScene?.interfaceOrientation ?? .portrait)
    }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: pinchStartZoom = displayZoom
        case .changed, .ended:
            ARCaptureCoordinator.shared.setDisplayZoom(pinchStartZoom * Double(gesture.scale)) { _ in }
        default: break
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Controls and constrained metric scrolling own their gestures; other readouts pass through.
        var view = touch.view
        while let current = view, current !== self {
            if current is UIControl || (current as? UIScrollView)?.isScrollEnabled == true { return false }
            view = current.superview
        }
        return true
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        if debugEnabled {
            let point = gesture.location(in: tagOverlay)
            guard tagOverlay.bounds.contains(point), let id = tagOverlay.tagID(at: point) else { return }
            ARCaptureCoordinator.shared.selectTag(id)
            return
        }
        if spatialMode == .selectFloor {
            let point = gesture.location(in: spatialOverlay)
            guard spatialOverlay.bounds.contains(point), let id = spatialOverlay.floorID(at: point) else { return }
            ARCaptureCoordinator.shared.selectFloor(id)
            return
        }
        let point = gesture.location(in: arView)
        guard arView.bounds.contains(point) else { return }
        ARCaptureCoordinator.shared.tap(point, in: arView.bounds.size, orientation: window?.windowScene?.interfaceOrientation ?? .portrait, displayZoom: displayZoom)
    }
    func updateLabel(_ status: [String: Any]) {
        let tracking = status["tracking"] as? String ?? "unavailable"
        let depth = status["depthAvailable"] as? Bool == true ? "LiDAR live" : "Waiting for depth"
        let count = (status["measurement"] as? [String: Any])?["pointCount"] as? Int ?? 0
        let mode = status["previewMode"] as? String ?? "camera"
        statusLabel.text = "\(tracking) · \(depth) · \(mode)\nTap two surfaces · \(count)/2 points · estimates only"
    }
    func setDebugMode(_ enabled: Bool) { debugEnabled = enabled; debugPanel.isHidden = !enabled; setNeedsLayout(); layoutIfNeeded() }
    func setDisplayZoom(_ factor: Double) {
        displayZoom = (try? PreviewZoom.clamped(factor)) ?? PreviewZoom.minimum
        applyDisplayZoom()
    }
    private func applyDisplayZoom() {
        let transform = CGAffineTransform(scaleX: CGFloat(displayZoom), y: CGFloat(displayZoom))
        arView.transform = transform; depthView.transform = transform
    }
    fileprivate func applySpatial(_ snapshot: SpatialRenderSnapshot) {
        spatialMode = snapshot.mode
        spatialOverlay.isHidden = !snapshot.visible
        guard snapshot.visible else { spatialOverlay.clear(); return }
        let age = ProcessInfo.processInfo.systemUptime - snapshot.timestamp
        spatialOverlay.show(planes: snapshot.planes, measurements: snapshot.measurements, pendingPoints: snapshot.pendingPoints,
            selectedFloorID: snapshot.selectedFloorID, isTrackingNormal: snapshot.isTrackingNormal && age >= 0 && age <= 0.5,
            cameraToWorld: snapshot.cameraToWorld, intrinsics: snapshot.intrinsics, imageSize: snapshot.imageSize,
            displayTransform: snapshot.displayTransform, expiresAt: snapshot.timestamp + 0.5, showImperialHeight: snapshot.showImperialHeight,
            pendingSelectedFloorID: snapshot.pendingSelectedFloorID, automaticTagHeights: snapshot.automaticTagHeights)
    }
    func clearAprilTagOverlay() { tagOverlay.clear(); debugPanel.showUnavailable("Waiting for a current visible tag") }
    func showAprilTagOverlay(_ detections: [[String: Any]], imageSize: CGSize, displayTransform: CGAffineTransform, frameID: String, expiresAt: Double, selectedID: Int? = nil, showPoseAxes: Bool = false, intrinsics: [Double]? = nil, showImperialHeight: Bool = true, distanceDeltaThresholdMeters: Double = 0.15) {
        tagOverlay.show(detections, imageSize: imageSize, displayTransform: displayTransform, frameID: frameID, expiresAt: expiresAt, selectedID: selectedID, showPoseAxes: showPoseAxes, intrinsics: intrinsics, showImperialHeight: showImperialHeight, distanceDeltaThresholdMeters: distanceDeltaThresholdMeters)
    }
}
