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

    private func cards() -> [UIView] {
        overlay.subviews.filter { $0.accessibilityIdentifier?.hasPrefix("apriltag.label.") == true }
    }
    private func cardLabel(_ card: UIView, _ field: String) -> UILabel? {
        card.subviews.compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier?.hasPrefix("apriltag.\(field).") == true
        }
    }
    private func cardText(_ card: UIView) -> String {
        var lines = [cardLabel(card, "summary")?.text ?? "", cardLabel(card, "distanceHeading")?.text ?? ""]
        for row in ["lidar", "tag", "delta"] {
            guard let title = cardLabel(card, row + "Title"), !title.isHidden else { continue }
            lines.append([title.text, cardLabel(card, row + "Metric")?.text, cardLabel(card, row + "English")?.text]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
    private func assertCardChildrenContained(_ card: UIView, file: StaticString = #filePath, line: UInt = #line) {
        for label in card.subviews.compactMap({ $0 as? UILabel }) {
            XCTAssertTrue(card.bounds.insetBy(dx: -0.01, dy: -0.01).contains(label.frame),
                "Card child outside bounds: \(label.accessibilityIdentifier ?? "") \(label.frame)", file: file, line: line)
        }
    }

    private func metricsRow(_ id: Int = 42, height: Double? = 1.42, lidar: Double? = 2.5,
                            tag: Double? = 2.55, rect: CGRect = CGRect(x: 40, y: 80, width: 70, height: 70)) -> [String: Any] {
        var row = detection(id)
        row["corners"] = [[rect.minX, rect.minY], [rect.maxX, rect.minY], [rect.maxX, rect.maxY], [rect.minX, rect.maxY]]
            .map { $0.map { NSNumber(value: Double($0)) } }
        row["floorHeight"] = ["available": height != nil, "meters": height as Any? ?? NSNull(),
            "source": height == nil ? "unavailable" : "sceneDepth", "reason": height == nil ? "floorNotSelected" : "valid"]
        row["cameraRanges"] = ["lidarAvailable": lidar != nil, "tagAvailable": tag != nil,
            "lidarRangeMeters": lidar as Any? ?? NSNull(), "tagRangeMeters": tag as Any? ?? NSNull(),
            "lidarDepthZMeters": 1.5, "tagDepthZMeters": 1.6, "lidarReason": "valid", "tagReason": "valid"]
        row["debug"] = ["severity": "good"]
        return row
    }

    private func saveOverlayPNG(_ name: String) throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: overlay.bounds, format: format).image { context in
            UIColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1).setFill(); context.fill(overlay.bounds)
            XCTAssertTrue(overlay.drawHierarchy(in: overlay.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("OVERLAY_PNG \(path.path)")
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

    func testKalmanReadoutsAreLabeledAndReuseClearsFilterIndicator() throws {
        var filter = TagReadoutFilter()
        var first = metricsRow(height: 1.42, lidar: 2.5, tag: 2.55)
        var height = first["floorHeight"] as! [String: Any]
        height["floorId"] = "floor"; height["segmentId"] = "segment"
        first["floorHeight"] = height
        _ = filter.apply(to: [first], timestamp: 10, enabled: true, samples: 5)
        var next = metricsRow(height: 1.72, lidar: 2.8, tag: 2.85)
        height["meters"] = 1.72; next["floorHeight"] = height
        let readouts = filter.apply(to: [next], timestamp: 10 + 1.0 / 30, enabled: true, samples: 5)
        overlay.show(readouts, imageSize: CGSize(width: 320, height: 480), displayTransform: .identity,
                     frameID: "filtered", expiresAt: ProcessInfo.processInfo.systemUptime + 0.5, showImperialHeight: false)
        overlay.layoutIfNeeded()
        let card = try XCTUnwrap(cards().first)
        XCTAssertEqual(cardLabel(card, "distanceHeading")?.text, "Distance · Kalman")
        XCTAssertTrue(cardLabel(card, "summary")?.text?.contains("152.0 cm") == true)
        XCTAssertEqual(cardLabel(card, "lidarMetric")?.text, "260.0 cm")
        XCTAssertEqual(cardLabel(card, "tagMetric")?.text, "265.0 cm")
        XCTAssertTrue(card.accessibilityValue?.contains("Kalman smoothing") == true)
        assertCardChildrenContained(card)
        XCTAssertEqual((next["floorHeight"] as? [String: Any])?["meters"] as? Double, 1.72)

        show([next])
        XCTAssertTrue(cards().first === card)
        XCTAssertEqual(cardLabel(card, "distanceHeading")?.text, "Distance")
        XCTAssertFalse(card.accessibilityValue?.contains("Kalman") == true)
    }

    func testARepeatedPositiveLabelsThenEmptyAndIdempotentClear() {
        for index in 0..<250 {
            autoreleasepool {
                show([detection(index)])
                XCTAssertEqual(cards().count, 1)
                XCTAssertEqual(overlay.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.count, 2)
                show([detection(index + 1), detection(index + 2)])
                XCTAssertEqual(cards().count, 2)
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
            let texts = self.cards().map(self.cardText)
            XCTAssertEqual(texts.count, 1)
            XCTAssertTrue(texts.first?.contains("#2") == true)
            checkedNewFrame.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            XCTAssertTrue(self.overlay.subviews.isEmpty)
            XCTAssertTrue(self.overlay.layer.sublayers?.isEmpty ?? true)
            XCTAssertNil(self.overlay.tagID(at: CGPoint(x: 80, y: 80)))
            self.overlay.clear()
            checkedFinalExpiry.fulfill()
        }
        wait(for: [checkedNewFrame, checkedFinalExpiry], timeout: 2)
    }

    func testDCurrentUpdatesReuseViewsAndDrawFourSelectableCorners() {
        show([detection()])
        let label = cards().first!
        let initialLayers = overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }
        for index in 0..<150 {
            show([detection()], frameID: "reuse-\(index)")
            XCTAssertTrue(cards().first === label)
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
        let texts = cards().map(cardText) + overlay.subviews.compactMap { ($0 as? UILabel)?.text }
        XCTAssertTrue(texts.contains { $0.contains("#42") })
        XCTAssertTrue(Set([" X ", " Y ", " Z "]).isSubset(of: Set(texts)))
    }

    func testHAxesReuseOwnedLayersAndToggleWithoutTouchingUIKitBackingLayers() {
        showAxes()
        let labels = overlay.subviews
        let shapes = overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }
        for _ in 0..<150 {
            showAxes()
            XCTAssertEqual(overlay.subviews.map(ObjectIdentifier.init), labels.map(ObjectIdentifier.init))
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
        let panel = TagDebugPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 44))
        panel.show(debug: ["id": 42, "status": "valid", "severity": "good",
            "floorHeight": ["available": true, "meters": 1.42, "source": "sceneDepth"]],
            frameID: "height-panel", timestamp: ProcessInfo.processInfo.systemUptime,
            analysisHz: 20, latencyMilliseconds: 5, settings: TagDebugSettings())
        panel.layoutIfNeeded()
        let title = try XCTUnwrap(panel.subviews.compactMap { $0 as? UILabel }.first { $0.text?.contains("TAG #42") == true })
        XCTAssertFalse(title.text?.contains("142.0 cm") == true,"Compact panel avoids repeating per-tag values")
        XCTAssertTrue(title.accessibilityLabel?.contains("142.0 cm (4 ft 7.9 in)") == true)
        XCTAssertTrue(panel.subviews.compactMap { ($0 as? UILabel)?.text }.contains { $0.contains("LiDAR") })
        XCTAssertTrue(title.isAccessibilityElement)
        XCTAssertEqual(panel.preferredHeight, 44)
        panel.setExpanded(true); panel.frame.size.height = panel.preferredHeight; panel.layoutIfNeeded()
        XCTAssertTrue(title.text?.contains("142.0 cm (4 ft 7.9 in)") == true)
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
        let labels = cards()
        XCTAssertEqual(labels.count, 2)
        XCTAssertTrue(cardText(labels[0]).contains("#42"))
        XCTAssertTrue(cardText(labels[0]).contains("142.0 cm (4 ft 7.9 in)"))
        XCTAssertTrue(cardText(labels[1]).contains("#42"))
        XCTAssertTrue(cardText(labels[1]).contains("231.0 cm (7 ft 6.9 in)"))
        XCTAssertTrue(labels[0].accessibilityValue?.contains("LiDAR depth") == true)
        XCTAssertTrue(labels[1].accessibilityValue?.contains("optical tag pose") == true)
        XCTAssertTrue(labels[1].accessibilityValue?.contains("poseFallbackMissingDepth") == true)
        for label in labels {
            XCTAssertEqual(label.accessibilityIdentifier, "apriltag.label.42")
            XCTAssertEqual(label.accessibilityLabel, "AprilTag 42")
            XCTAssertTrue(label.isAccessibilityElement)
            XCTAssertEqual(cardLabel(label, "summary")?.font.pointSize, 12)
        }
        let ids = labels.map(ObjectIdentifier.init)
        for _ in 0..<30 { show([lidar, optical]) }
        XCTAssertEqual(cards().map(ObjectIdentifier.init), ids)
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
            let label = try XCTUnwrap(cards().first)
            XCTAssertTrue(cardText(label).contains("#42"))
            XCTAssertTrue(cardText(label).contains("—"))
            XCTAssertFalse(cardText(label).contains("0.000"))
            XCTAssertTrue(label.accessibilityValue?.contains("height unavailable") == true)
        }
        var noFloor = detection()
        noFloor["floorHeight"] = ["available": false, "source": "unavailable", "reason": "floorNotSelected"]
        show([noFloor])
        XCTAssertTrue(cards().first?.accessibilityValue?.contains("set a floor") == true)
        show([detection()])
        XCTAssertTrue(cards().first.map(cardText)?.contains("#42") == true)
    }

    func testAutomaticHeightLabelFitsNarrowViewportAndSelectionRetainsReadableTagID() throws {
        overlay.frame.size = CGSize(width: 140, height: 240)
        var row = detection(587)
        row["floorHeight"] = ["available": true, "meters": 12.345, "source": "sceneDepth", "reason": "valid"]
        overlay.show([row], imageSize: CGSize(width: 320, height: 480), displayTransform: .identity,
            frameID: "height-selected", expiresAt: ProcessInfo.processInfo.systemUptime + 0.5, selectedID: 587)
        overlay.layoutIfNeeded()
        let label = try XCTUnwrap(cards().first)
        XCTAssertTrue(cardText(label).contains("◆ #587"))
        XCTAssertTrue(cardText(label).contains("1234.5 cm (40 ft 6.0 in)"))
        XCTAssertTrue(overlay.bounds.contains(label.frame))
        XCTAssertTrue(cardLabel(label, "summary")?.adjustsFontSizeToFitWidth == true)
        XCTAssertTrue(label.accessibilityTraits.contains(.selected))
        XCTAssertEqual(overlay.tagID(at: CGPoint(x: 40, y: 50)), 587)
    }

    func testAutomaticTagHeightUnitsToggleReusesLabelsAndPreservesRawMeters() throws {
        var row = detection()
        let height: [String: Any] = ["available": true, "meters": 1.423456789, "source": "sceneDepth", "reason": "valid"]
        row["floorHeight"] = height
        let original = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        show([row])
        let label = try XCTUnwrap(cards().first)
        XCTAssertTrue(cardText(label).contains("142.3 cm (4 ft 8.0 in)"))
        overlay.show([row], imageSize: CGSize(width: 320, height: 480), displayTransform: .identity,
            frameID: "height-metric-only", expiresAt: ProcessInfo.processInfo.systemUptime + 0.5,
            showImperialHeight: false)
        XCTAssertTrue(cards().first === label)
        XCTAssertTrue(cardText(label).contains("142.3 cm"))
        XCTAssertFalse(cardText(label).contains(" ft "))
        XCTAssertFalse(label.accessibilityValue?.contains(" ft ") == true)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), original)
        XCTAssertEqual((row["floorHeight"] as? [String: Any])?["meters"] as? Double, 1.423456789)
    }

    func testCompactCardsShowBothTrueRangesWithoutAConfirmedFloorAndRespectUnits() throws {
        let row = metricsRow(height: nil)
        show([row])
        let label = try XCTUnwrap(cards().first)
        XCTAssertEqual(cardLabel(label, "distanceHeading")?.text, "Distance")
        XCTAssertEqual(cardLabel(label, "lidarMetric")?.font.pointSize, 12)
        XCTAssertFalse(try XCTUnwrap(cardLabel(label, "lidarMetric")).font.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(cardText(label).contains("250.0 cm (8 ft 2.4 in)"))
        XCTAssertTrue(cardText(label).contains("255.0 cm (8 ft 4.4 in)"))
        XCTAssertFalse(cardText(label).contains("150.0 cm"),"Raw optical Z is not camera-to-tag range")
        XCTAssertFalse(cardText(label).contains("160.0 cm"))
        XCTAssertTrue(label.accessibilityValue?.contains("set a floor") == true)
        XCTAssertTrue(label.accessibilityValue?.contains("250.0 cm") == true)
        XCTAssertTrue(try XCTUnwrap(label.backgroundColor).cgColor.alpha < 0.9)
        XCTAssertLessThanOrEqual(label.layer.borderWidth, 1.5)
        overlay.show([row], imageSize: CGSize(width: 320, height: 480), displayTransform: .identity,
            frameID: "ranges-metric-only", expiresAt: ProcessInfo.processInfo.systemUptime + 0.5, showImperialHeight: false)
        XCTAssertTrue(cardText(label).contains("250.0 cm"))
        XCTAssertTrue(cardText(label).contains("255.0 cm"))
        XCTAssertFalse(cardText(label).contains(" ft "))
        XCTAssertFalse(label.accessibilityValue?.contains(" ft ") == true)
    }

    func testDuplicateIDsKeepTheirOwnCameraRangesAndMalformedRangesStayUnavailable() throws {
        show([metricsRow(42, lidar: 2.5, tag: 2.55), metricsRow(42, lidar: 3.5, tag: 3.55)])
        let labels = cards()
        XCTAssertEqual(labels.count, 2)
        XCTAssertTrue(cardText(labels[0]).contains("250.0 cm"))
        XCTAssertFalse(cardText(labels[0]).contains("350.0 cm"))
        XCTAssertTrue(cardText(labels[1]).contains("350.0 cm"))
        var row = metricsRow()
        for invalid in ([0, -1, Double.nan, Double.infinity, true] as [Any]) {
            row["cameraRanges"] = ["lidarAvailable": true, "tagAvailable": true, "lidarRangeMeters": invalid, "tagRangeMeters": invalid]
            show([row])
            let card = try XCTUnwrap(cards().first)
            XCTAssertEqual(cardLabel(card, "lidarMetric")?.text, "—")
            XCTAssertEqual(cardLabel(card, "tagMetric")?.text, "—")
        }
        row["cameraRanges"] = ["lidarAvailable": false, "tagAvailable": false, "lidarRangeMeters": 2.5, "tagRangeMeters": 2.55]
        show([row])
        XCTAssertFalse(cards().first.map(cardText)?.contains("250.0 cm") == true)
    }

    func testFourNeighboringCardsStaySelectableAndDoNotOverlapWhenThereIsSpace() throws {
        overlay.frame.size = CGSize(width: 390, height: 600)
        let positions: [CGPoint] = [CGPoint(x: 50, y: 100), CGPoint(x: 250, y: 100), CGPoint(x: 50, y: 370), CGPoint(x: 250, y: 370)]
        let ranges = [(2.95, 3.3), (0.95, 1.3), (2.5, 2.55), (2.8, 3.15)]
        let rows = positions.enumerated().map { index, position in
            metricsRow(index + 4, height: index == 1 ? 0.42 : 1.42 + Double(index) * 0.1,
                lidar: ranges[index].0, tag: ranges[index].1,
                rect: CGRect(origin: position, size: CGSize(width: 70, height: 70)))
        }
        overlay.show(rows, imageSize: overlay.bounds.size, displayTransform: .identity,
            frameID: "four-neighboring-tags", expiresAt: ProcessInfo.processInfo.systemUptime + 2)
        overlay.layoutIfNeeded(); CATransaction.flush()
        let labels = cards()
        XCTAssertEqual(labels.count, 4)
        for (index, label) in labels.enumerated() {
            XCTAssertTrue(overlay.bounds.contains(label.frame))
            XCTAssertGreaterThanOrEqual(label.frame.minY, 88)
            assertCardChildrenContained(label)
            XCTAssertEqual(overlay.tagID(at: CGPoint(x: label.frame.midX, y: label.frame.midY)), index + 4)
            for other in labels.dropFirst(index + 1) {
                XCTAssertFalse(label.frame.insetBy(dx: 0.5, dy: 0.5).intersects(other.frame.insetBy(dx: 0.5, dy: 0.5)),
                    "Neighboring readouts overlap despite available vertical space")
            }
        }
        try saveOverlayPNG("four-tag-compact-ranges-390x600")
    }

    func testCompactCardRemainsContainedInATinyViewport() throws {
        overlay.frame.size = CGSize(width: 80, height: 24)
        show([metricsRow()])
        let label = try XCTUnwrap(cards().first)
        XCTAssertTrue(overlay.bounds.contains(label.frame))
        assertCardChildrenContained(label)
        XCTAssertTrue(label.accessibilityValue?.contains("142.0 cm") == true)
    }

    func testVisibleCardHitTakesPriorityOverAnotherTagsCoveringQuad() throws {
        let first = metricsRow(42)
        var covering = metricsRow(17)
        covering["corners"] = [[0, 0], [320, 0], [320, 480], [0, 480]].map { $0.map(NSNumber.init(value:)) }
        show([first, covering])
        let labels = cards()
        XCTAssertEqual(labels.count, 2)
        XCTAssertFalse(labels[0].frame.intersects(labels[1].frame))
        XCTAssertEqual(overlay.tagID(at: CGPoint(x: labels[0].frame.midX, y: labels[0].frame.midY)), 42,
            "The second tag quad covers the viewport but must not steal a visible first-card tap")
        XCTAssertEqual(overlay.tagID(at: CGPoint(x: labels[1].frame.midX, y: labels[1].frame.midY)), 17)
    }

    func testCompactRangeCardsExpireTogetherWithoutAnotherFrame() {
        let expired = expectation(description: "per-tag range cards expired")
        show([metricsRow(), metricsRow(17)], lifetime: 0.04)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            XCTAssertTrue(self.overlay.subviews.isEmpty)
            XCTAssertNil(self.overlay.tagID(at: CGPoint(x: 80, y: 100)))
            expired.fulfill()
        }
        wait(for: [expired], timeout: 2)
    }

    func testDistanceHeadingAndMetricDecimalsShareAColumnIndependentOfEnglishDigitLengths() throws {
        show([metricsRow(lidar: 2.95, tag: 10.3)])
        let card = try XCTUnwrap(cards().first)
        XCTAssertEqual(cardLabel(card, "distanceHeading")?.text, "Distance")
        let lidar = try XCTUnwrap(cardLabel(card, "lidarMetric")), tag = try XCTUnwrap(cardLabel(card, "tagMetric"))
        let lidarEnglish = try XCTUnwrap(cardLabel(card, "lidarEnglish")), tagEnglish = try XCTUnwrap(cardLabel(card, "tagEnglish"))
        XCTAssertEqual(lidar.text, "295.0 cm")
        XCTAssertEqual(tag.text, "1030.0 cm")
        XCTAssertEqual(lidar.textAlignment, .right); XCTAssertEqual(tag.textAlignment, .right)
        XCTAssertEqual(lidar.frame.minX, tag.frame.minX, accuracy: 0.01)
        XCTAssertEqual(lidar.frame.maxX, tag.frame.maxX, accuracy: 0.01)
        XCTAssertEqual(lidar.font, tag.font)
        XCTAssertEqual(lidar.font.pointSize, 12)
        XCTAssertEqual(lidarEnglish.frame.minX, tagEnglish.frame.minX, accuracy: 0.01)
        XCTAssertGreaterThan(lidarEnglish.frame.minX, lidar.frame.maxX)
        XCTAssertNotEqual(lidarEnglish.intrinsicContentSize.width, tagEnglish.intrinsicContentSize.width)
        XCTAssertEqual(lidar.frame.midY, lidarEnglish.frame.midY, accuracy: 0.01)
        XCTAssertEqual(tag.frame.midY, tagEnglish.frame.midY, accuracy: 0.01)
        assertCardChildrenContained(card)
    }

    func testRangeDeltaAppearsOnlyStrictlyAboveThresholdAndUsesIndependentAmberColor() throws {
        func render(_ delta: Double, threshold: Double = 0.15) throws -> UIView {
            var row = metricsRow(lidar: 2, tag: 2 + delta)
            var ranges = row["cameraRanges"] as! [String: Any]; ranges["distanceDeltaMeters"] = delta
            row["cameraRanges"] = ranges
            overlay.show([row], imageSize: CGSize(width: 320, height: 480), displayTransform: .identity,
                frameID: UUID().uuidString, expiresAt: ProcessInfo.processInfo.systemUptime + 0.5,
                distanceDeltaThresholdMeters: threshold)
            return try XCTUnwrap(cards().first)
        }
        let card = try render(0.15)
        XCTAssertTrue(try XCTUnwrap(cardLabel(card, "deltaTitle")).isHidden)
        XCTAssertFalse(card.accessibilityValue?.contains("Absolute LiDAR versus Tag") == true)
        let originalHeight = card.bounds.height
        let originalIDs = card.subviews.map(ObjectIdentifier.init)
        XCTAssertTrue(try render(0.15000001) === card)
        XCTAssertFalse(try XCTUnwrap(cardLabel(card, "deltaTitle")).isHidden)
        XCTAssertEqual(cardLabel(card, "deltaTitle")?.text, "LiDAR Δ")
        XCTAssertEqual(cardLabel(card, "deltaMetric")?.text, "15.0 cm")
        XCTAssertEqual(cardLabel(card, "deltaEnglish")?.text, "(0 ft 5.9 in)")
        XCTAssertEqual(cardLabel(card, "deltaMetric")?.textColor, .systemOrange)
        XCTAssertEqual(cardLabel(card, "lidarMetric")?.textColor, .systemGreen)
        XCTAssertTrue(card.accessibilityValue?.contains("Absolute LiDAR versus Tag camera range difference: 15.0 cm") == true)
        XCTAssertGreaterThan(card.bounds.height, originalHeight)
        XCTAssertEqual(card.subviews.map(ObjectIdentifier.init), originalIDs)
        assertCardChildrenContained(card)
        _ = try render(0.2, threshold: 0.25)
        XCTAssertTrue(try XCTUnwrap(cardLabel(card, "deltaTitle")).isHidden)
        XCTAssertEqual(card.bounds.height, originalHeight)
        _ = try render(0.25, threshold: 0.25)
        XCTAssertTrue(try XCTUnwrap(cardLabel(card, "deltaTitle")).isHidden)
    }

    func testDeltaIgnoresAxialZDifferenceAndRejectsMissingOrInconsistentRangeMetadata() throws {
        var row = metricsRow(lidar: 2, tag: 2.05)
        row["debug"] = ["severity": "good", "depthDifferenceMeters": 10]
        var ranges = row["cameraRanges"] as! [String: Any]
        ranges["distanceDeltaMeters"] = 10 // Cannot masquerade as the true-range difference.
        row["cameraRanges"] = ranges
        show([row])
        XCTAssertTrue(try XCTUnwrap(cardLabel(XCTUnwrap(cards().first), "deltaTitle")).isHidden)
        for missing in [metricsRow(lidar: nil, tag: 3), metricsRow(lidar: 2, tag: nil)] {
            show([missing])
            XCTAssertTrue(try XCTUnwrap(cardLabel(XCTUnwrap(cards().first), "deltaTitle")).isHidden)
        }
        ranges["lidarAvailable"] = 1
        row["cameraRanges"] = ranges
        show([row])
        XCTAssertEqual(cardLabel(try XCTUnwrap(cards().first), "lidarMetric")?.text, "—")
        XCTAssertTrue(try XCTUnwrap(cardLabel(XCTUnwrap(cards().first), "deltaTitle")).isHidden)
        show([metricsRow(lidar: 2, tag: 2.5)]) // Trusted fallback if an older record lacks delta metadata.
        XCTAssertEqual(cardLabel(try XCTUnwrap(cards().first), "deltaMetric")?.text, "50.0 cm")
        overlay.show([metricsRow(lidar: 2, tag: 2.5)], imageSize: CGSize(width: 320, height: 480),
            displayTransform: .identity, frameID: "metric-delta", expiresAt: ProcessInfo.processInfo.systemUptime + 0.5,
            showImperialHeight: false)
        let card = try XCTUnwrap(cards().first)
        XCTAssertEqual(cardLabel(card, "deltaMetric")?.text, "50.0 cm")
        XCTAssertTrue(try XCTUnwrap(cardLabel(card, "deltaEnglish")).isHidden)
        XCTAssertFalse(card.accessibilityValue?.contains(" ft ") == true)
    }
}
