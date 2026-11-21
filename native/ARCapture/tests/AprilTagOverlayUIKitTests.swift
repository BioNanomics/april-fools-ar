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
}
