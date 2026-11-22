import XCTest
import UIKit

/// Runs against the actual production UIView in a minimal UIKit simulator host.
@MainActor
final class AprilTagOverlayUIKitTests: XCTestCase {
    private var overlay: AprilTagOverlayView!

    override func setUp() {
        super.setUp()
        XCTAssertTrue(Thread.isMainThread)
        let window = UIApplication.shared.windows.first { $0.isKeyWindow }!
        overlay = AprilTagOverlayView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController!.view.addSubview(overlay)
        window.layoutIfNeeded()
    }

    override func tearDown() {
        overlay?.clear()
        overlay?.removeFromSuperview()
        overlay = nil
        super.tearDown()
    }

    private func detection(_ id: Int = 42) -> [String: Any] {
        ["id": NSNumber(value: id), "corners": [[40, 50], [160, 50], [160, 170], [40, 170]].map { $0.map(NSNumber.init(value:)) }]
    }

    private func show(_ detections: [[String: Any]], frameID: String = UUID().uuidString, lifetime: Double = 0.5) {
        overlay.show(detections, imageSize: CGSize(width: 320, height: 480), displayTransform: .identity, frameID: frameID, expiresAt: ProcessInfo.processInfo.systemUptime + lifetime)
        overlay.layoutIfNeeded()
        CATransaction.flush()
    }

    private func pose(translation: [Double] = [0, 0, 2], rotation: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]) -> [String: Any] {
        ["translation": translation.map(NSNumber.init(value:)), "rotationRowMajor": rotation.map(NSNumber.init(value:)), "tagSizeMeters": NSNumber(value: 0.2)]
    }

    private func showAxes(transform: CGAffineTransform = .identity, enabled: Bool = true, lifetime: Double = 0.5) {
        var tag = detection(); tag["pose"] = pose()
        overlay.show([tag], imageSize: CGSize(width: 320, height: 480), displayTransform: transform,
                     frameID: UUID().uuidString, expiresAt: ProcessInfo.processInfo.systemUptime + lifetime,
                     showPoseAxes: enabled, intrinsics: [500, 600, 160, 240])
        overlay.layoutIfNeeded(); CATransaction.flush()
    }

    private func assertPoint(_ value: CGPoint?, _ x: Double, _ y: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let value else { XCTFail("Expected a projected point", file: file, line: line); return }
        XCTAssertEqual(Double(value.x), x, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(Double(value.y), y, accuracy: 1e-8, file: file, line: line)
    }

    func testARepeatedPositiveLabelsThenEmptyAndIdempotentClear() {
        for index in 0..<250 {
            autoreleasepool {
                show([detection(index)])
                XCTAssertEqual(overlay.subviews.compactMap { $0 as? UILabel }.count, 1)
                XCTAssertEqual(overlay.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.count, 2)
                show([detection(index + 1), detection(index + 2)])
                XCTAssertEqual(overlay.subviews.compactMap { $0 as? UILabel }.count, 2)
                XCTAssertEqual(overlay.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.count, 4)
                show([])
                overlay.clear(); overlay.clear()
                XCTAssertTrue(overlay.subviews.isEmpty)
                XCTAssertTrue(overlay.layer.sublayers?.isEmpty ?? true)
            }
        }
    }

    func testBClearPreservesUnrelatedUIKitViewAndLayer() {
        let unrelatedView = UIView(frame: CGRect(x: 2, y: 2, width: 8, height: 8))
        let unrelatedLayer = CALayer()
        unrelatedLayer.frame = CGRect(x: 12, y: 12, width: 8, height: 8)
        overlay.addSubview(unrelatedView)
        overlay.layer.addSublayer(unrelatedLayer)
        for _ in 0..<20 {
            show([detection()])
            XCTAssertTrue(unrelatedView.superview === overlay)
            XCTAssertTrue(unrelatedLayer.superlayer === overlay.layer)
            overlay.clear()
            XCTAssertTrue(unrelatedView.superview === overlay)
            XCTAssertTrue(unrelatedLayer.superlayer === overlay.layer)
            XCTAssertEqual(overlay.subviews.count, 1)
            XCTAssertEqual(overlay.layer.sublayers?.count, 2)
        }
        unrelatedView.removeFromSuperview()
        unrelatedLayer.removeFromSuperlayer()
    }

    func testCExpiryClearsLabelsWithoutOldTimerClearingNewFrame() {
        let checkedNewFrame = expectation(description: "new frame survives old expiry")
        let checkedFinalExpiry = expectation(description: "new frame expires")
        show([detection(1)], frameID: "old", lifetime: 0.06)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            self.show([self.detection(2)], frameID: "new", lifetime: 0.20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            XCTAssertEqual(self.overlay.subviews.compactMap { ($0 as? UILabel)?.text }, [" #2 "])
            checkedNewFrame.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            XCTAssertTrue(self.overlay.subviews.isEmpty)
            XCTAssertTrue(self.overlay.layer.sublayers?.isEmpty ?? true)
            self.overlay.clear()
            checkedFinalExpiry.fulfill()
        }
        wait(for: [checkedNewFrame, checkedFinalExpiry], timeout: 2)
    }

    func testDCurrentUpdatesReuseViewsAndDrawFourSelectableCorners() {
        show([detection()])
        let label = overlay.subviews.compactMap { $0 as? UILabel }.first!
        let initialLayers = overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }
        for index in 0..<150 {
            show([detection()], frameID: "reuse-\(index)")
            XCTAssertTrue(overlay.subviews.compactMap { $0 as? UILabel }.first === label)
            let layers = overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }
            XCTAssertEqual(layers.count, 2)
            XCTAssertTrue(layers[0] === initialLayers[0]); XCTAssertTrue(layers[1] === initialLayers[1])
            XCTAssertEqual(overlay.tagID(at: CGPoint(x: 80, y: 80)), 42)
            XCTAssertNil(overlay.tagID(at: CGPoint(x: 300, y: 400)))
        }
        var circleMoves = 0
        initialLayers[1].path!.applyWithBlock { if $0.pointee.type == .moveToPoint { circleMoves += 1 } }
        XCTAssertEqual(circleMoves, 4)
    }

    func testEIdentityAndOffAxisRotatedPoseProjectCameraCoordinates() throws {
        let k = [500.0, 600, 160, 240]
        let identity = try XCTUnwrap(AprilTagOverlayView.projectPoseAxes(pose: pose(), intrinsics: k))
        assertPoint(identity.origin, 160, 240)
        assertPoint(identity.endpoints[0], 185, 240)
        assertPoint(identity.endpoints[1], 160, 270)
        assertPoint(identity.endpoints[2], 160, 240) // Head-on Z is foreshortened, not a made-up screen direction.
        let rotated = pose(translation: [0.4, -0.2, 2], rotation: [0, -1, 0, 1, 0, 0, 0, 0, 1])
        let offAxis = try XCTUnwrap(AprilTagOverlayView.projectPoseAxes(pose: rotated, intrinsics: k))
        assertPoint(offAxis.origin, 260, 180)
        assertPoint(offAxis.endpoints[0], 260, 210) // Tag X follows the first R column, not first row.
        assertPoint(offAxis.endpoints[1], 235, 180)
        assertPoint(offAxis.endpoints[2], 160 + 200 / 2.1, 240 - 120 / 2.1)
        let longer = try XCTUnwrap(AprilTagOverlayView.projectPoseAxes(pose: pose(), intrinsics: k, axisLengthMeters: 0.2))
        assertPoint(longer.endpoints[0], 210, 240)
    }

    func testFInvalidPoseAndCalibrationNeverDrawPlausibleAxes() throws {
        let k = [500.0, 600, 160, 240]
        XCTAssertNil(AprilTagOverlayView.projectPoseAxes(pose: [:], intrinsics: k))
        for bad in [[0.0, 600, 160, 240], [500, .nan, 160, 240], [500, 600, 160]] {
            XCTAssertNil(AprilTagOverlayView.projectPoseAxes(pose: pose(), intrinsics: bad))
        }
        for z in [0.0, -2, .nan] {
            XCTAssertNil(AprilTagOverlayView.projectPoseAxes(pose: pose(translation: [0, 0, z]), intrinsics: k))
        }
        XCTAssertNil(AprilTagOverlayView.projectPoseAxes(pose: pose(rotation: [1, 0, 0, 0, 1, 0, 0, 0, -1]), intrinsics: k))
        XCTAssertNil(AprilTagOverlayView.projectPoseAxes(pose: pose(rotation: [1, 0, 0, 0, .nan, 0, 0, 0, 1]), intrinsics: k))
        for length in [0.0, -0.1, .infinity] {
            XCTAssertNil(AprilTagOverlayView.projectPoseAxes(pose: pose(), intrinsics: k, axisLengthMeters: length))
        }
        let crossing = pose(translation: [0, 0, 0.05], rotation: [0, 0, 1, 0, 1, 0, -1, 0, 0])
        let clipped = try XCTUnwrap(AprilTagOverlayView.projectPoseAxes(pose: crossing, intrinsics: k))
        XCTAssertNil(clipped.endpoints[0])
        XCTAssertNotNil(clipped.endpoints[1]); XCTAssertNotNil(clipped.endpoints[2])
    }

    func testGAxesUseDisplayTransformAndDegenerateZHasVisibleDot() throws {
        showAxes(transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0))
        let shapes = overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }
        XCTAssertEqual(shapes.count, 5)
        let axes = Array(shapes.suffix(3))
        var vertices = [CGPoint]()
        axes[0].path!.applyWithBlock { element in
            if vertices.count < 2, element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint { vertices.append(element.pointee.points[0]) }
        }
        XCTAssertEqual(vertices.count, 2)
        assertPoint(vertices[0], 160, 240); assertPoint(vertices[1], 160, 277.5)
        let zBounds = try XCTUnwrap(axes[2].path?.boundingBoxOfPath)
        XCTAssertGreaterThanOrEqual(zBounds.width, 6); XCTAssertGreaterThanOrEqual(zBounds.height, 6)
        XCTAssertEqual(Set(overlay.subviews.compactMap { ($0 as? UILabel)?.text }), Set([" #42 ", " X ", " Y ", " Z "]))
    }

    func testHAxesReuseOwnedLayersAndToggleWithoutTouchingUIKitBackingLayers() {
        showAxes()
        let labels = overlay.subviews.compactMap { $0 as? UILabel }
        let shapes = overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }
        for _ in 0..<150 {
            showAxes()
            XCTAssertEqual(overlay.subviews.compactMap { $0 as? UILabel }.map(ObjectIdentifier.init), labels.map(ObjectIdentifier.init))
            XCTAssertEqual(overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }.map(ObjectIdentifier.init), shapes.map(ObjectIdentifier.init))
        }
        showAxes(enabled: false)
        XCTAssertEqual(overlay.subviews.count, 1)
        XCTAssertEqual(overlay.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.count, 2)
        showAxes(); overlay.clear(); overlay.clear()
        XCTAssertTrue(overlay.subviews.isEmpty); XCTAssertTrue(overlay.layer.sublayers?.isEmpty ?? true)
    }

    func testIAxesExpireWithTheirSourceFrame() {
        let expired = expectation(description: "axis layers and labels expire")
        showAxes(lifetime: 0.04)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            XCTAssertTrue(self.overlay.subviews.isEmpty)
            XCTAssertTrue(self.overlay.layer.sublayers?.isEmpty ?? true)
            expired.fulfill()
        }
        wait(for: [expired], timeout: 2)
    }

    func testSelectedPanelHeightTitleAndAccessibilityClearWhenUnavailable() throws {
        let panel = TagDebugPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 96))
        panel.show(debug: ["id": 42, "status": "valid", "severity": "good",
            "floorHeight": ["available": true, "meters": 1.42, "source": "sceneDepth"]],
            frameID: "height-panel", timestamp: ProcessInfo.processInfo.systemUptime,
            analysisHz: 20, latencyMilliseconds: 5, settings: TagDebugSettings())
        panel.layoutIfNeeded()
        let title = try XCTUnwrap(panel.subviews.compactMap { $0 as? UILabel }.first { $0.text?.contains("TAG #42") == true })
        XCTAssertTrue(title.text?.contains("142.0 cm (4 ft 7.9 in)") == true)
        XCTAssertTrue(title.accessibilityLabel?.contains("142.0 cm (4 ft 7.9 in)") == true)
        XCTAssertTrue(panel.subviews.compactMap { ($0 as? UILabel)?.text }.contains { $0.contains("LiDAR") })
        XCTAssertTrue(title.isAccessibilityElement)
        XCTAssertEqual(panel.preferredHeight, 96)
        var metricSettings = TagDebugSettings(); metricSettings.showImperialHeight = false
        panel.show(debug: ["id": 42, "status": "valid", "severity": "good",
            "floorHeight": ["available": true, "meters": 1.42, "source": "sceneDepth"]],
            frameID: "height-panel-metric", timestamp: ProcessInfo.processInfo.systemUptime,
            analysisHz: 20, latencyMilliseconds: 5, settings: metricSettings)
        XCTAssertTrue(title.text?.contains("142.0 cm") == true)
        XCTAssertFalse(title.text?.contains(" ft ") == true)
        XCTAssertTrue(title.accessibilityLabel?.contains("142.0 cm") == true)
        XCTAssertFalse(title.accessibilityLabel?.contains(" ft ") == true)
        panel.showUnavailable("Stale result")
        XCTAssertFalse(title.text?.contains("142.0") == true)
        XCTAssertFalse(title.accessibilityLabel?.contains("142.0") == true)
        XCTAssertEqual(title.accessibilityLabel, "TAG DEBUG · WAITING")
    }

    func testAutomaticHeightsStayWithEachDetectionEvenWhenTagIDsAreDuplicated() throws {
        var lidar = detection(42), optical = detection(42)
        lidar["floorHeight"] = ["available": true, "meters": 1.42, "source": "sceneDepth", "reason": "valid"]
        optical["floorHeight"] = ["available": true, "meters": 2.31, "source": "tagPose", "reason": "poseFallbackMissingDepth"]
        optical["corners"] = [[190, 200], [290, 200], [290, 300], [190, 300]].map { $0.map(NSNumber.init(value:)) }
        show([lidar, optical])
        let labels = overlay.subviews.compactMap { $0 as? UILabel }
        XCTAssertEqual(labels.count, 2)
        XCTAssertTrue(labels[0].text?.contains("#42 · ↑ 142.0 cm (4 ft 7.9 in)") == true)
        XCTAssertTrue(labels[1].text?.contains("#42 · ↑ 231.0 cm (7 ft 6.9 in)") == true)
        XCTAssertTrue(labels[0].accessibilityValue?.contains("LiDAR depth") == true)
        XCTAssertTrue(labels[1].accessibilityValue?.contains("optical tag pose") == true)
        XCTAssertTrue(labels[1].accessibilityValue?.contains("poseFallbackMissingDepth") == true)
        for label in labels {
            XCTAssertEqual(label.accessibilityIdentifier, "apriltag.label.42")
            XCTAssertEqual(label.accessibilityLabel, "AprilTag 42")
            XCTAssertTrue(label.isAccessibilityElement)
            XCTAssertEqual(label.font.pointSize, 17)
        }
        let ids = labels.map(ObjectIdentifier.init)
        for _ in 0..<30 { show([lidar, optical]) }
        XCTAssertEqual(overlay.subviews.compactMap { $0 as? UILabel }.map(ObjectIdentifier.init), ids)
    }

    func testUnavailableOrMalformedAutomaticHeightNeverDisplaysAFakeZero() throws {
        let records: [[String: Any]] = [
            ["available": false, "meters": 0, "source": "unavailable", "reason": "floorNotSelected"],
            ["available": true, "meters": Double.nan, "source": "sceneDepth"],
            ["available": true, "meters": Double.infinity, "source": "tagPose"],
            ["available": true, "meters": -1, "source": "sceneDepth"],
            ["available": true, "meters": true, "source": "sceneDepth"],
            ["available": true, "meters": 1.42, "source": "unknown-source"]]
        for record in records {
            var row = detection(); row["floorHeight"] = record
            show([row])
            let label = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first)
            XCTAssertEqual(label.text, " #42 · H — ")
            XCTAssertFalse(label.text?.contains("0.000") == true)
            XCTAssertTrue(label.accessibilityValue?.contains("height unavailable") == true)
        }
        var noFloor = detection()
        noFloor["floorHeight"] = ["available": false, "source": "unavailable", "reason": "floorNotSelected"]
        show([noFloor])
        XCTAssertTrue(overlay.subviews.compactMap { $0 as? UILabel }.first?.accessibilityValue?.contains("set a floor") == true)
        show([detection()])
        XCTAssertEqual(overlay.subviews.compactMap { ($0 as? UILabel)?.text }, [" #42 "])
    }

    func testAutomaticHeightLabelFitsNarrowViewportAndSelectionRetainsReadableTagID() throws {
        overlay.frame.size = CGSize(width: 140, height: 240)
        var row = detection(587)
        row["floorHeight"] = ["available": true, "meters": 12.345, "source": "sceneDepth", "reason": "valid"]
        overlay.show([row], imageSize: CGSize(width: 320, height: 480), displayTransform: .identity,
            frameID: "height-selected", expiresAt: ProcessInfo.processInfo.systemUptime + 0.5, selectedID: 587)
        overlay.layoutIfNeeded()
        let label = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertTrue(label.text?.contains("◆ #587") == true)
        XCTAssertTrue(label.text?.contains("1234.5 cm (40 ft 6.0 in)") == true)
        XCTAssertTrue(overlay.bounds.contains(label.frame))
        XCTAssertTrue(label.adjustsFontSizeToFitWidth)
        XCTAssertTrue(label.accessibilityTraits.contains(.selected))
        XCTAssertEqual(overlay.tagID(at: CGPoint(x: 40, y: 50)), 587)
    }

    func testAutomaticTagHeightUnitsToggleReusesLabelsAndPreservesRawMeters() throws {
        var row = detection()
        let height: [String: Any] = ["available": true, "meters": 1.423456789, "source": "sceneDepth", "reason": "valid"]
        row["floorHeight"] = height
        let original = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        show([row])
        let label = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertTrue(label.text?.contains("142.3 cm (4 ft 8.0 in)") == true)
        overlay.show([row], imageSize: CGSize(width: 320, height: 480), displayTransform: .identity,
            frameID: "height-metric-only", expiresAt: ProcessInfo.processInfo.systemUptime + 0.5,
            showImperialHeight: false)
        XCTAssertTrue(overlay.subviews.compactMap { $0 as? UILabel }.first === label)
        XCTAssertTrue(label.text?.contains("142.3 cm") == true)
        XCTAssertFalse(label.text?.contains(" ft ") == true)
        XCTAssertFalse(label.accessibilityValue?.contains(" ft ") == true)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), original)
        XCTAssertEqual((row["floorHeight"] as? [String: Any])?["meters"] as? Double, 1.423456789)
    }
}
