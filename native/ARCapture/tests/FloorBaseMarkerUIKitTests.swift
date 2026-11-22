import XCTest
import UIKit
import simd

@MainActor
final class FloorBaseMarkerUIKitTests: XCTestCase {
    private let image = CGSize(width: 640, height: 480)
    private let k = simd_float3x3(columns: ([420, 0, 0], [0, 510, 0], [300, 220, 1]))
    private var cameraPose: simd_float4x4 {
        var pose = simd_float4x4(simd_quatf(angle: -.pi/4, axis: [1, 0, 0]))
        pose.columns.3 = [0, 3, 0, 1]
        return pose
    }
    private func floor(tilt: Double = 0, known: Bool = true, center: SIMD3<Float> = [0, 0, -3], id: String = "floor") -> SpatialPlane {
        let normal = SIMD3<Float>(-Float(tan(tilt * .pi/180)), 1, 0)
        let corners: [SIMD3<Float>] = [[-2, 0, -2], [2, 0, -2], [2, 0, 2], [-2, 0, 2]]
        return SpatialPlane(id: id, classification: "floor", origin: center, normal: normal,
            vertices: corners.map { center + SIMD3<Float>($0.x, -normal.x*$0.x, $0.z) },
            segmentID: "segment", frameID: "floor-frame", timestamp: 1,
            tiltSource: known ? "sceneDepth-plane-fit" : "unavailable")
    }
    private func manual(_ floor: SpatialPlane?, kind: String = "height", id: String = "manual", center: SIMD3<Float>? = nil, height: Float = 1.5) -> SpatialMeasurement {
        let start = center ?? floor?.origin ?? SIMD3<Float>(0, 0, -3)
        return SpatialMeasurement(id: id, kind: kind, start: start, end: start + [0, height, 0],
            segmentID: "segment", timestamp: 2, sourcePoints: [], floor: floor)
    }
    private func automatic(_ floor: SpatialPlane, timestamp: Double, height: Double = 1.5) throws -> TagHeightVector {
        var basis = floor.dictionary; basis["operatorConfirmed"] = true
        let start = floor.origin, end = start + SIMD3<Float>(0, Float(height), 0)
        let detection: [String: Any] = ["id": 42, "floorHeight": ["available": true, "meters": height,
            "source": "sceneDepth", "severity": "good", "frameId": "tag-frame", "segmentId": "segment",
            "timestamp": timestamp, "floorId": floor.id, "floor": basis,
            "floorFootWorldMeters": SpatialMeasurementMath.array(start), "worldMeters": SpatialMeasurementMath.array(end)]]
        return try XCTUnwrap(TagHeightVectors.make(from: [detection], floor: floor, segmentID: "segment", frameID: "tag-frame",
            tracking: "normal", mode: .height, now: ProcessInfo.processInfo.systemUptime).first)
    }
    private func show(_ view: SpatialMeasurementOverlayView, manual: [SpatialMeasurement] = [], automatic: [TagHeightVector] = [],
                      pose: simd_float4x4? = nil, transform: CGAffineTransform = .identity, deadline: Double? = nil, tracking: Bool = true) {
        view.show(planes: [], measurements: manual, pendingPoints: [], selectedFloorID: nil, isTrackingNormal: tracking,
            cameraToWorld: pose ?? cameraPose, intrinsics: k, imageSize: image, displayTransform: transform,
            expiresAt: deadline ?? ProcessInfo.processInfo.systemUptime + 1, automaticTagHeights: automatic)
    }
    private func patches(_ view: UIView) -> [CAShapeLayer] {
        (view.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.filter { $0.name?.hasPrefix("spatial.floorBase.") == true }
    }
    private func pathEdges(_ layer: CAShapeLayer) -> (edges: [(CGPoint, CGPoint)], closes: Int) {
        var edges = [(CGPoint, CGPoint)](), closes = 0, previous: CGPoint?
        layer.path?.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: previous = element.pointee.points[0]
            case .addLineToPoint:
                if let a = previous { edges.append((a, element.pointee.points[0])) }
                previous = element.pointee.points[0]
            case .closeSubpath: closes += 1
            default: XCTFail("A floor square must contain only independent original line edges")
            }
        }
        return (edges, closes)
    }
    private func projected(_ world: SIMD3<Float>, pose: simd_float4x4, display: CGAffineTransform, viewport: CGSize) -> CGPoint {
        let point = simd_inverse(pose) * SIMD4<Float>(world, 1)
        let x = Double(k[0][0]) * Double(point.x) / -Double(point.z) + Double(k[2][0])
        let y = Double(k[1][1]) * -Double(point.y) / -Double(point.z) + Double(k[2][1])
        let normalized = CGPoint(x: x/image.width, y: y/image.height).applying(display)
        return CGPoint(x: normalized.x*viewport.width, y: normalized.y*viewport.height)
    }
    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.02, file: file, line: line)
    }
    private func assertColor(_ layer: CAShapeLayer, _ expected: UIColor, file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = UIColor(cgColor: try XCTUnwrap(layer.strokeColor))
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        expected.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        for (x, y) in zip([ar, ag, ab, aa], [br, bg, bb, ba]) { XCTAssertEqual(x, y, accuracy: 1e-4, file: file, line: line) }
    }

    func testOriginalSquareEdgesProjectThroughCameraRotationTiltPortraitAndZoomInWideAndTallViews() throws {
        let datum = floor(tilt: 8), marker = try XCTUnwrap(FloorBaseMarker.make(center: floor(tilt: 8).origin, floor: floor(tilt: 8)))
        for viewport in [CGSize(width: 390, height: 520), CGSize(width: 760, height: 420)] {
            let view = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: viewport))
            defer { view.clear() }
            for zoom in [1.0, 2, 4] {
                let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
                let display = PreviewZoom.displayTransform(base: portrait, zoom: zoom)
                show(view, manual: [manual(datum)], transform: display)
                let patch = try XCTUnwrap(patches(view).first), path = pathEdges(patch)
                XCTAssertEqual(path.closes, 0)
                XCTAssertEqual(path.edges.count, 4)
                for index in 0..<4 {
                    assertPoint(path.edges[index].0, projected(marker.corners[index], pose: cameraPose, display: display, viewport: viewport))
                    assertPoint(path.edges[index].1, projected(marker.corners[(index+1)%4], pose: cameraPose, display: display, viewport: viewport))
                }
                XCTAssertEqual(marker.center, datum.origin)
                XCTAssertNil(view.floorID(at: CGPoint(x: viewport.width/2, y: viewport.height/2)))
                XCTAssertNil(view.hitTest(CGPoint(x: viewport.width/2, y: viewport.height/2), with: nil))
            }
        }
    }

    func testEffectiveFloorControlsDottedColorAndAccessibilityWithoutChangingObservedTilt() throws {
        let view = SpatialMeasurementOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 520))
        defer { view.clear() }
        let tilted = floor(tilt: 10), leveled = SpatialMeasurementMath.effectiveFloor(tilted, levelWithGravity: true)
        let cases: [(SpatialPlane, UIColor, String)] = [(floor(), .systemGreen, "Base plane level"),
            (tilted, .systemYellow, "Base plane tilted"), (floor(known: false), .lightGray, "Base plane tilt unavailable"),
            (leveled, .systemGreen, "Base plane level")]
        for (datum, color, accessibility) in cases {
            show(view, manual: [manual(datum)])
            let patch = try XCTUnwrap(patches(view).first)
            try assertColor(patch, color)
            XCTAssertEqual(patch.lineWidth, 1.5)
            XCTAssertEqual(patch.lineCap, .round)
            XCTAssertEqual(patch.lineDashPattern?.map(\.intValue), [1, 4])
            XCTAssertEqual(patch.fillColor?.alpha, 0)
            let label = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
            XCTAssertTrue(label.accessibilityValue?.contains(accessibility) == true)
        }
        XCTAssertEqual(try XCTUnwrap(leveled.observedTiltDegrees), 10, accuracy: 1e-5)
        XCTAssertEqual(leveled.normal, SIMD3<Float>(0, 1, 0))
        XCTAssertTrue(try XCTUnwrap(FloorBaseMarker.make(center: leveled.origin, floor: leveled)).corners.allSatisfy { abs($0.y-leveled.origin.y) < 1e-6 })
    }

    func testNearPlaneClipsOriginalEdgesWithoutInventedViewportBoundaryConnections() throws {
        let view = SpatialMeasurementOverlayView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        defer { view.clear() }
        let datum = floor(center: [0, -0.03, -0.08])
        show(view, manual: [manual(datum, height: 0.05)], pose: matrix_identity_float4x4)
        let patch = try XCTUnwrap(patches(view).first), path = pathEdges(patch)
        let marker = try XCTUnwrap(FloorBaseMarker.make(center: datum.origin, floor: datum))
        let camera = try XCTUnwrap(SpatialProjection.Camera(cameraToWorld: matrix_identity_float4x4, intrinsics: k, imageSize: image,
            displayTransform: .identity, viewportSize: view.bounds.size))
        let expected = (0..<4).compactMap { camera.segment(from: marker.corners[$0], to: marker.corners[($0+1)%4]) }
        XCTAssertEqual(path.closes, 0)
        XCTAssertEqual(path.edges.count, expected.count)
        XCTAssertLessThan(path.edges.count, 4)
        XCTAssertFalse(path.edges.isEmpty)
        for (edge, clipped) in zip(path.edges, expected) { assertPoint(edge.0, clipped[0]); assertPoint(edge.1, clipped[1]) }
        for edge in path.edges { for p in [edge.0, edge.1] {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            XCTAssertTrue(view.bounds.insetBy(dx: -0.01, dy: -0.01).contains(p))
        } }
    }

    func testOwnerReuseDistancePendingMissingFloorTrackingAndClearNeverLeaveAPatch() throws {
        let view = SpatialMeasurementOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 520)), datum = floor()
        let foreign = CALayer(); view.layer.addSublayer(foreign)
        show(view, manual: [manual(datum)])
        let patch = try XCTUnwrap(patches(view).first), identities = (view.layer.sublayers ?? []).map(ObjectIdentifier.init)
        for _ in 0..<100 { show(view, manual: [manual(datum)]) }
        XCTAssertEqual((view.layer.sublayers ?? []).map(ObjectIdentifier.init), identities)
        show(view, manual: [manual(datum, kind: "distance")])
        XCTAssertNil(patch.path); XCTAssertTrue(patch.isHidden)
        show(view, manual: [manual(nil)])
        XCTAssertTrue(patches(view).isEmpty)
        XCTAssertTrue(view.subviews.compactMap { $0 as? UILabel }.first?.accessibilityValue?.contains("tilt unavailable") == true)
        show(view, manual: [manual(datum)])
        XCTAssertTrue(patches(view).first === patch)
        show(view, manual: [manual(datum)], tracking: false)
        XCTAssertNil(patch.superlayer)
        XCTAssertTrue(foreign.superlayer === view.layer)
        show(view, manual: [manual(datum)])
        view.show(planes: [], measurements: [], pendingPoints: [[0, 0, -3]], selectedFloorID: nil, isTrackingNormal: true,
            cameraToWorld: cameraPose, intrinsics: k, imageSize: image, displayTransform: .identity)
        XCTAssertTrue(patches(view).isEmpty)
        view.clear(); view.clear()
        XCTAssertEqual(view.layer.sublayers?.count, 1)
        XCTAssertTrue(foreign.superlayer === view.layer)
    }

    func testAutomaticSourceExpiryHidesItsBaseBeforeCameraDeadlineAndSceneExpiryRemovesManualBase() throws {
        let view = SpatialMeasurementOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 520)), datum = floor()
        defer { view.clear() }
        let now = ProcessInfo.processInfo.systemUptime
        show(view, automatic: [try automatic(datum, timestamp: now-0.3)], deadline: now+1)
        let patch = try XCTUnwrap(patches(view).first)
        XCTAssertFalse(patch.isHidden)
        let sourceExpired = expectation(description: "source height/base expire together")
        DispatchQueue.main.asyncAfter(deadline: .now()+0.25) { XCTAssertTrue(patch.isHidden); sourceExpired.fulfill() }
        wait(for: [sourceExpired], timeout: 1)
        show(view, manual: [manual(datum)], deadline: ProcessInfo.processInfo.systemUptime+0.1)
        let manualPatch = try XCTUnwrap(patches(view).first)
        let sceneExpired = expectation(description: "scene removes owned base")
        DispatchQueue.main.asyncAfter(deadline: .now()+0.25) { XCTAssertNil(manualPatch.superlayer); sceneExpired.fulfill() }
        wait(for: [sceneExpired], timeout: 1)
    }

    func testManualGreenAndAutomaticYellowFloorBasesRenderInWideViewport() throws {
        let view = SpatialMeasurementOverlayView(frame: CGRect(x: 0, y: 0, width: 640, height: 420))
        let window = UIWindow(frame: view.bounds); window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(view); window.makeKeyAndVisible()
        defer { view.clear(); window.isHidden = true }
        let level = floor(center: [-0.7, 0, -3], id: "level"), tilted = floor(tilt: 6, center: [0.7, 0, -3], id: "tilted")
        show(view, manual: [manual(level)], automatic: [try automatic(tilted, timestamp: ProcessInfo.processInfo.systemUptime)],
            transform: PreviewZoom.normalizedTransform(for: 2))
        XCTAssertEqual(patches(view).count, 2)
        try assertColor(try XCTUnwrap(patches(view).first { $0.name?.contains("manual") == true }), .systemGreen)
        try assertColor(try XCTUnwrap(patches(view).first { $0.name?.contains("tag") == true }), .systemYellow)
        view.layoutIfNeeded(); CATransaction.flush()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        let png = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            UIColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1).setFill(); context.fill(view.bounds)
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: png); attachment.name = "floor-base-green-yellow-wide"; attachment.lifetime = .keepAlways; add(attachment)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("floor-base-green-yellow-wide.png")
        try XCTUnwrap(png.pngData()).write(to: path); print("OVERLAY_PNG \(path.path)")
    }
}
