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
}
