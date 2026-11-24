import XCTest
import UIKit
import simd

@MainActor
final class SpatialProjectionUIKitTests: XCTestCase {
    private let k = simd_float3x3(columns: ([100, 0, 0], [0, 100, 0], [100, 100, 1]))
    private let size = CGSize(width: 200, height: 200)
    private func camera() throws -> SpatialProjection.Camera {
        try XCTUnwrap(SpatialProjection.Camera(cameraToWorld: matrix_identity_float4x4, intrinsics: k,
            imageSize: size, displayTransform: .identity, viewportSize: size))
    }
    private func plane(_ id: String = "floor-A", classification: String = "floor") -> SpatialPlane {
        SpatialPlane(id: id, classification: classification, origin: [0, 0, -1], normal: [0, 1, 0],
            vertices: [[-0.6, -0.3, -1], [0.6, -0.3, -1], [0.6, 0.3, -1], [-0.6, 0.3, -1]],
            segmentID: "segment-A", frameID: "frame-A", timestamp: 1)
    }
    private func vector(_ id: String = "vector-A", kind: String = "distance") -> SpatialMeasurement {
        SpatialMeasurement(id: id, kind: kind, start: [-0.4, -0.2, -1], end: [0.4, 0.2, -1],
            segmentID: "segment-A", timestamp: 1, sourcePoints: [], floor: nil)
    }
    private func show(_ overlay: SpatialMeasurementOverlayView, planes: [SpatialPlane] = [],
                      vectors: [SpatialMeasurement] = [], pending: [SIMD3<Float>] = [],
                      selected: String? = nil, tracking: Bool = true, showImperial: Bool = true, pendingFloor: String? = nil) {
        overlay.show(planes: planes, measurements: vectors, pendingPoints: pending,
            selectedFloorID: selected, isTrackingNormal: tracking, cameraToWorld: matrix_identity_float4x4,
            intrinsics: k, imageSize: size, displayTransform: .identity, showImperialHeight: showImperial,
            pendingSelectedFloorID: pendingFloor)
    }
    private func assertInside(_ points: [CGPoint], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(points.isEmpty, file: file, line: line)
        for point in points {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite, file: file, line: line)
            XCTAssertGreaterThanOrEqual(point.x, -1e-4, file: file, line: line)
            XCTAssertLessThanOrEqual(point.x, 200.0001, file: file, line: line)
            XCTAssertGreaterThanOrEqual(point.y, -1e-4, file: file, line: line)
            XCTAssertLessThanOrEqual(point.y, 200.0001, file: file, line: line)
        }
    }
    private func label(_ overlay: UIView, _ identifier: String) throws -> UILabel {
        try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == identifier })
    }
    private func shape(_ overlay: UIView, _ identifier: String) throws -> CAShapeLayer {
        try XCTUnwrap(overlay.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.name == identifier })
    }
    private func pathPoints(_ path: CGPath?) -> [(CGPathElementType, CGPoint)] {
        var elements = [(CGPathElementType, CGPoint)]()
        path?.applyWithBlock { element in
            let type = element.pointee.type
            elements.append((type, type == .closeSubpath ? .zero : element.pointee.points[0]))
        }
        return elements
    }
    private func assertOpenEdge(_ shape: CAShapeLayer, from start: CGPoint, to end: CGPoint,
                                file: StaticString = #filePath, line: UInt = #line) {
        let points = pathPoints(shape.path)
        XCTAssertEqual(points.count, 2, file: file, line: line)
        guard points.count == 2 else { return }
        XCTAssertEqual(points[0].0, .moveToPoint, file: file, line: line)
        XCTAssertEqual(points[1].0, .addLineToPoint, file: file, line: line)
        XCTAssertEqual(points[0].1.x, start.x, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(points[0].1.y, start.y, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(points[1].1.x, end.x, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(points[1].1.y, end.y, accuracy: 1e-3, file: file, line: line)
    }

    func testDistanceTriangleShowsThreeFourFiveComponentsAndSignedVertical() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let measurement = SpatialMeasurement(id: "triangle", kind: "distance", start: [-1.5, -2, -8], end: [1.5, 2, -8],
            segmentID: "segment-A", timestamp: 1, sourcePoints: [], floor: nil)
        show(overlay, vectors: [measurement])
        let direct = try label(overlay, "spatial.measurement.triangle")
        XCTAssertEqual(direct.text, " D 5.000 m ")
        XCTAssertEqual(try label(overlay, "spatial.measurement.triangle.horizontal").text, " H 3.000 m ")
        XCTAssertEqual(try label(overlay, "spatial.measurement.triangle.vertical").text, " V +4.000 m ")
        XCTAssertTrue(direct.accessibilityValue?.contains("Direct distance 5.000 meters. Horizontal distance 3.000 meters. Signed vertical difference +4.000 meters") == true)
        let horizontal = try shape(overlay, "spatial.measurement.triangle.horizontal")
        let vertical = try shape(overlay, "spatial.measurement.triangle.vertical")
        XCTAssertEqual(horizontal.lineDashPattern, [5, 4])
        XCTAssertEqual(vertical.lineDashPattern, [5, 4])
        XCTAssertEqual(horizontal.strokeColor, UIColor.systemCyan.cgColor)
        XCTAssertEqual(vertical.strokeColor, UIColor.systemOrange.cgColor)
        assertOpenEdge(horizontal, from: CGPoint(x: 81.25, y: 125), to: CGPoint(x: 118.75, y: 125))
        assertOpenEdge(vertical, from: CGPoint(x: 118.75, y: 125), to: CGPoint(x: 118.75, y: 75))
        let downward = SpatialMeasurement(id: "down", kind: "distance", start: measurement.end, end: measurement.start,
            segmentID: "segment-A", timestamp: 1, sourcePoints: [], floor: nil)
        show(overlay, vectors: [downward])
        XCTAssertEqual(try label(overlay, "spatial.measurement.down.vertical").text, " V -4.000 m ")
        XCTAssertTrue(try label(overlay, "spatial.measurement.down").accessibilityValue?.contains("Signed vertical difference -4.000 meters") == true)
    }

    func testDistanceTriangleRotatesAndZoomsWithCameraRatherThanAssumingScreenAxes() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let pose = simd_float4x4(columns: ([0, 1, 0, 0], [-1, 0, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]))
        overlay.show(planes: [], measurements: [vector()], pendingPoints: [], selectedFloorID: nil,
            isTrackingNormal: true, cameraToWorld: pose, intrinsics: k, imageSize: size,
            displayTransform: PreviewZoom.displayTransform(base: .identity, zoom: 2))
        assertOpenEdge(try shape(overlay, "spatial.measurement.vector-A.horizontal"),
            from: CGPoint(x: 60, y: 20), to: CGPoint(x: 60, y: 180))
        assertOpenEdge(try shape(overlay, "spatial.measurement.vector-A.vertical"),
            from: CGPoint(x: 60, y: 180), to: CGPoint(x: 140, y: 180))
        XCTAssertEqual(try label(overlay, "spatial.measurement.vector-A.horizontal").text, " H 0.800 m ")
        XCTAssertEqual(try label(overlay, "spatial.measurement.vector-A.vertical").text, " V +0.400 m ")
    }

    func testDistanceTriangleClipsLegsIndependentlyWhenDiagonalIsEntirelyOffscreen() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let measurement = SpatialMeasurement(id: "clipped", kind: "distance", start: [2, 0.5, -1], end: [-0.5, 2, -1],
            segmentID: "segment-A", timestamp: 1, sourcePoints: [], floor: nil)
        XCTAssertNil(try camera().segment(from: measurement.start, to: measurement.end))
        show(overlay, vectors: [measurement])
        let direct = try shape(overlay, "spatial.measurement.clipped.diagonal")
        XCTAssertTrue(direct.isHidden)
        XCTAssertNil(direct.path)
        assertOpenEdge(try shape(overlay, "spatial.measurement.clipped.horizontal"),
            from: CGPoint(x: 200, y: 50), to: CGPoint(x: 50, y: 50))
        assertOpenEdge(try shape(overlay, "spatial.measurement.clipped.vertical"),
            from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 0))
        XCTAssertFalse(try label(overlay, "spatial.measurement.clipped").isHidden)
        for visible in overlay.subviews.compactMap({ $0 as? UILabel }) where !visible.isHidden {
            XCTAssertTrue(overlay.bounds.contains(visible.frame))
        }
    }

    func testDegenerateDistanceTrianglesShowZeroValuesWithoutOverlappingLegsOrPendingTriangles() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let endpoints: [(SIMD3<Float>, SIMD3<Float>, String)] = [
            ([-0.4, 0, -1], [0.4, 0, -1], " D 0.800 m · H 0.800 m · V +0.000 m "),
            ([0, -0.2, -1], [0, 0.2, -1], " D 0.400 m · H 0.000 m · V +0.400 m "),
            ([0, 0, -1], [0, 0, -1], " D 0.000 m · H 0.000 m · V +0.000 m ")]
        for (start, end, expected) in endpoints {
            let measurement = SpatialMeasurement(id: "zero", kind: "distance", start: start, end: end,
                segmentID: "segment-A", timestamp: 1, sourcePoints: [], floor: nil)
            show(overlay, vectors: [measurement])
            let summary = try label(overlay, "spatial.measurement.zero")
            XCTAssertEqual(summary.text, expected)
            XCTAssertEqual(summary.numberOfLines, 0)
            XCTAssertEqual(summary.lineBreakMode, .byWordWrapping)
            XCTAssertTrue(overlay.bounds.contains(summary.frame))
            let fitted = summary.sizeThatFits(CGSize(width: summary.bounds.width, height: CGFloat.greatestFiniteMagnitude))
            XCTAssertLessThanOrEqual(fitted.width, summary.bounds.width + 0.5)
            XCTAssertLessThanOrEqual(fitted.height, summary.bounds.height + 0.5, "Every D/H/V value must fit, including V zero")
            XCTAssertGreaterThan(summary.bounds.height, summary.font.lineHeight, "The 200-pixel viewport needs a wrapped summary")
            for suffix in ["horizontal", "vertical"] {
                let leg = try shape(overlay, "spatial.measurement.zero.\(suffix)")
                XCTAssertTrue(leg.isHidden)
                XCTAssertNil(leg.path)
                XCTAssertTrue(try label(overlay, "spatial.measurement.zero.\(suffix)").isHidden)
            }
        }
        show(overlay, vectors: [vector()])
        let direct = try label(overlay, "spatial.measurement.vector-A")
        XCTAssertEqual(direct.numberOfLines, 1, "A reused normal distance label returns to one line")
        XCTAssertEqual(direct.lineBreakMode, .byTruncatingTail)
        show(overlay, vectors: [vector(kind: "height")], pending: [[-0.4, 0, -1], [0.4, 0, -1]])
        XCTAssertEqual(try label(overlay, "spatial.measurement.vector-A").numberOfLines, 1)
        XCTAssertFalse(overlay.layer.sublayers?.contains { $0.name?.hasSuffix(".horizontal") == true || $0.name?.hasSuffix(".vertical") == true } == true)
        XCTAssertEqual(overlay.subviews.compactMap { $0 as? UILabel }.count, 3)
        show(overlay, pending: [[-0.4, 0, -1], [0.4, 0, -1]])
        XCTAssertEqual(overlay.subviews.compactMap { $0 as? UILabel }.count, 2)
    }

    func testDegenerateDistanceSummaryScreenshotFitsTwoHundredPixelViewport() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let window = try XCTUnwrap(UIApplication.shared.windows.first { $0.isKeyWindow })
        let host = try XCTUnwrap(window.rootViewController?.view)
        host.addSubview(overlay)
        defer { overlay.clear(); overlay.removeFromSuperview() }
        let measurement = SpatialMeasurement(id: "degenerate", kind: "distance", start: [-0.4, 0, -1], end: [0.4, 0, -1],
            segmentID: "segment-A", timestamp: 1, sourcePoints: [], floor: nil)
        show(overlay, vectors: [measurement])
        window.layoutIfNeeded(); overlay.layoutIfNeeded(); CATransaction.flush()
        let summary = try label(overlay, "spatial.measurement.degenerate")
        let fitted = summary.sizeThatFits(CGSize(width: summary.bounds.width, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertLessThanOrEqual(fitted.width, summary.bounds.width + 0.5)
        XCTAssertLessThanOrEqual(fitted.height, summary.bounds.height + 0.5)
        XCTAssertTrue(summary.text?.contains("V +0.000 m") == true)
        let image = UIGraphicsImageRenderer(bounds: overlay.bounds).image { context in
            UIColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1).setFill(); context.fill(overlay.bounds)
            XCTAssertTrue(overlay.drawHierarchy(in: overlay.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image); attachment.name = "distance-triangle-degenerate-200"
        attachment.lifetime = .keepAlways; add(attachment)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("distance-triangle-degenerate-200.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("OVERLAY_PNG \(path.path)")
    }

    func testDistanceTriangleScreenshot() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 480))
        let window = try XCTUnwrap(UIApplication.shared.windows.first { $0.isKeyWindow })
        let host = try XCTUnwrap(window.rootViewController?.view)
        host.addSubview(overlay)
        defer { overlay.clear(); overlay.removeFromSuperview() }
        let calibration = simd_float3x3(columns: ([250, 0, 0], [0, 250, 0], [195, 240, 1]))
        let measurement = SpatialMeasurement(id: "three-four-five", kind: "distance", start: [-1.5, -2, -4], end: [1.5, 2, -4],
            segmentID: "segment-A", timestamp: 1, sourcePoints: [], floor: nil)
        overlay.show(planes: [], measurements: [measurement], pendingPoints: [], selectedFloorID: nil,
            isTrackingNormal: true, cameraToWorld: matrix_identity_float4x4, intrinsics: calibration,
            imageSize: overlay.bounds.size, displayTransform: .identity)
        window.layoutIfNeeded(); overlay.layoutIfNeeded(); CATransaction.flush()
        let image = UIGraphicsImageRenderer(bounds: overlay.bounds).image { context in
            UIColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1).setFill(); context.fill(overlay.bounds)
            XCTAssertTrue(overlay.drawHierarchy(in: overlay.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image); attachment.name = "distance-triangle-three-four-five"
        attachment.lifetime = .keepAlways; add(attachment)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("distance-triangle-three-four-five.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("OVERLAY_PNG \(path.path)")
    }

    func testNonidentityCameraAsymmetricIntrinsicsPortraitAndCenteredZoomHaveKnownPixelCoordinates() throws {
        // Camera is rotated +90 degrees around world Z and translated (1,2,3).
        let pose = simd_float4x4(columns: ([0, 1, 0, 0], [-1, 0, 0, 0], [0, 0, 1, 0], [1, 2, 3, 1]))
        let asymmetricK = simd_float3x3(columns: ([500, 0, 0], [0, 700, 0], [130, 90, 1]))
        let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        // World (1.08,2.04,1) is camera (.04,-.08,-2): sensor pixel (140,118).
        let expected: [(Double, CGFloat, CGFloat)] = [(1, 198.25, 369.25), (2, 201.5, 316.5), (4, 208, 211)]
        for (zoom, x, y) in expected {
            let projection = try XCTUnwrap(SpatialProjection.Camera(cameraToWorld: pose, intrinsics: asymmetricK,
                imageSize: CGSize(width: 320, height: 240),
                displayTransform: PreviewZoom.displayTransform(base: portrait, zoom: zoom),
                viewportSize: CGSize(width: 390, height: 844)))
            let point = try XCTUnwrap(projection.point([1.08, 2.04, 1]))
            XCTAssertEqual(point.x, x, accuracy: 0.01)
            XCTAssertEqual(point.y, y, accuracy: 0.01)
        }
    }

    func testNearPlaneAndViewportClippingRetainCrossingLineInsteadOfDroppingIt() throws {
        let projection = try camera()
        let segment = try XCTUnwrap(projection.segment(from: [-0.02, 0, 0.02], to: [0.02, 0, -0.2]))
        XCTAssertEqual(segment.count, 2)
        XCTAssertEqual(segment[0].x, 0, accuracy: 1e-3)
        XCTAssertEqual(segment[0].y, 100, accuracy: 1e-3)
        XCTAssertEqual(segment[1].x, 110, accuracy: 1e-3)
        assertInside(segment)
        XCTAssertNil(projection.segment(from: [0, 0, 0.1], to: [1, 0, 1]))
        XCTAssertNil(projection.point([0, 0, 0.001]))
        let fullWidth = try XCTUnwrap(projection.segment(from: [-2, 0, -1], to: [2, 0, -1]))
        XCTAssertEqual(fullWidth[0].x, 0, accuracy: 1e-3)
        XCTAssertEqual(fullWidth[1].x, 200, accuracy: 1e-3)
    }

    func testNearPlanePolygonCrossingCameraIsClippedToFiniteVisibleHitGeometry() throws {
        let projection = try camera()
        let polygon = projection.polygon([[-0.2, -0.1, -0.2], [0.2, -0.1, -0.2], [0.2, 0.1, 0.1], [-0.2, 0.1, 0.1]])
        XCTAssertGreaterThanOrEqual(polygon.count, 3)
        assertInside(polygon)
        XCTAssertTrue(projection.polygon([[-1, 0, 1], [1, 0, 1], [0, 1, 1]]).isEmpty)
        XCTAssertTrue(projection.polygon([[0, 0, -1], [.nan, 0, -1], [1, 1, -1]]).isEmpty)
    }

    func testInvalidProjectionInputsFailClosed() {
        let zeroPose = simd_float4x4(diagonal: SIMD4<Float>(repeating: 0))
        XCTAssertNil(SpatialProjection.Camera(cameraToWorld: zeroPose, intrinsics: k, imageSize: size, displayTransform: .identity, viewportSize: size))
        XCTAssertNil(SpatialProjection.Camera(cameraToWorld: matrix_identity_float4x4, intrinsics: k, imageSize: .zero, displayTransform: .identity, viewportSize: size))
        XCTAssertNil(SpatialProjection.Camera(cameraToWorld: matrix_identity_float4x4, intrinsics: k, imageSize: size, displayTransform: .init(scaleX: 0, y: 1), viewportSize: size))
        XCTAssertNil(SpatialProjection.Camera(cameraToWorld: matrix_identity_float4x4, intrinsics: k, imageSize: size, displayTransform: .identity, viewportSize: size, nearPlaneMeters: .nan))
    }

    func testRendererLabelsHitTestingTrackingHideAndOwnedCleanup() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let foreignLayer = CALayer(); overlay.layer.addSublayer(foreignLayer)
        let foreignView = UIView(); overlay.addSubview(foreignView)
        show(overlay, planes: [plane()], vectors: [vector()], pending: [[0, 0, -1]], selected: "floor-A")
        XCTAssertEqual(overlay.floorPlaneID(at: CGPoint(x: 100, y: 100)), "floor-A")
        XCTAssertNil(overlay.floorPlaneID(at: CGPoint(x: 5, y: 5)))
        XCTAssertNil(overlay.hitTest(CGPoint(x: 100, y: 100), with: nil))
        let labels = overlay.subviews.compactMap { $0 as? UILabel }
        XCTAssertEqual(labels.count, 5)
        XCTAssertEqual(labels.first { $0.accessibilityIdentifier == "spatial.plane.floor-A" }?.accessibilityLabel, "Floor selected")
        XCTAssertTrue(labels.contains { $0.text?.contains("D 0.894 m") == true })
        XCTAssertTrue(labels.contains { $0.text?.contains("H 0.800 m") == true })
        XCTAssertTrue(labels.contains { $0.text?.contains("V +0.400 m") == true })
        XCTAssertTrue(labels.contains { $0.accessibilityIdentifier == "spatial.pending.1" })
        for label in labels {
            XCTAssertEqual(label.font.pointSize, 12)
            XCTAssertTrue(overlay.bounds.contains(label.frame))
        }
        show(overlay, planes: [plane()], vectors: [vector()], tracking: false)
        XCTAssertNil(overlay.floorID(at: CGPoint(x: 100, y: 100)))
        XCTAssertFalse(overlay.subviews.contains { $0 is UILabel })
        XCTAssertTrue(foreignView.superview === overlay)
        XCTAssertTrue(foreignLayer.superlayer === overlay.layer)
        show(overlay, planes: [plane()], vectors: [vector()])
        XCTAssertEqual(overlay.floorID(at: CGPoint(x: 100, y: 100)), "floor-A")
        overlay.clear()
        XCTAssertTrue(foreignView.superview === overlay)
        XCTAssertTrue(foreignLayer.superlayer === overlay.layer)
        XCTAssertNil(overlay.floorID(at: CGPoint(x: 100, y: 100)))
    }

    func testRendererExpiresLabelsAndHitPathsWithoutAnotherCameraCallback() async throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let foreignLayer = CALayer(); overlay.layer.addSublayer(foreignLayer)
        overlay.show(planes: [plane()], measurements: [vector()], pendingPoints: [[0, 0, -1]],
            selectedFloorID: "floor-A", isTrackingNormal: true, cameraToWorld: matrix_identity_float4x4,
            intrinsics: k, imageSize: size, displayTransform: .identity,
            expiresAt: ProcessInfo.processInfo.systemUptime + 0.1)
        XCTAssertEqual(overlay.subviews.compactMap { $0 as? UILabel }.count, 5)
        XCTAssertEqual(overlay.floorPlaneID(at: CGPoint(x: 100, y: 100)), "floor-A")
        // Yield the main actor; no show/clear call simulates an entirely stopped AR callback stream.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(overlay.subviews.contains { $0 is UILabel })
        XCTAssertNil(overlay.floorPlaneID(at: CGPoint(x: 100, y: 100)))
        XCTAssertTrue(foreignLayer.superlayer === overlay.layer)
        XCTAssertEqual(overlay.layer.sublayers?.count, 1)
    }

    func testRendererCapsPoolsAndReusesViewsAndLayersAcrossFrames() {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let planes = (0..<30).map { plane("floor-\($0)", classification: "unclassified") }
        let vectors = (0..<60).map { vector("vector-\($0)", kind: $0 == 59 ? "height" : "distance") }
        let pending: [SIMD3<Float>] = [[0, 0, -1], [0.1, 0, -1], [0.2, 0, -1]]
        show(overlay, planes: planes, vectors: vectors, pending: pending, selected: "floor-29")
        let labels = overlay.subviews.compactMap { $0 as? UILabel }
        XCTAssertEqual(labels.count, 24 + 50 + 49 * 2 + 2)
        XCTAssertTrue(labels.contains { $0.accessibilityIdentifier == "spatial.plane.floor-29" })
        XCTAssertTrue(labels.contains { $0.accessibilityLabel == "Horizontal surface candidate" })
        XCTAssertTrue(labels.contains { $0.accessibilityIdentifier == "spatial.measurement.vector-59" && $0.text?.contains("Height") == true })
        XCTAssertFalse(labels.contains { $0.accessibilityIdentifier == "spatial.measurement.vector-0" })
        let viewIDs = overlay.subviews.map(ObjectIdentifier.init)
        let layerIDs = (overlay.layer.sublayers ?? []).map(ObjectIdentifier.init)
        for _ in 0..<100 { show(overlay, planes: planes, vectors: vectors, pending: pending, selected: "floor-29") }
        XCTAssertEqual(overlay.subviews.map(ObjectIdentifier.init), viewIDs)
        XCTAssertEqual((overlay.layer.sublayers ?? []).map(ObjectIdentifier.init), layerIDs)
    }

    func testOnlyHeightVectorLabelsUseCentimetersAndOptionalEnglishUnits() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        let height = vector("height", kind: "height"), distance = vector("distance")
        let original = try JSONSerialization.data(withJSONObject: height.dictionary, options: [.sortedKeys])
        show(overlay, vectors: [height, distance])
        let labels = overlay.subviews.compactMap { $0 as? UILabel }
        let heightLabel = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "spatial.measurement.height" })
        let distanceLabel = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "spatial.measurement.distance" })
        XCTAssertTrue(heightLabel.text?.contains("40.0 cm (1 ft 3.7 in)") == true)
        XCTAssertTrue(heightLabel.accessibilityValue?.contains("40.0 cm (1 ft 3.7 in)") == true)
        XCTAssertTrue(distanceLabel.text?.contains("0.894 m") == true)
        XCTAssertFalse(distanceLabel.text?.contains(" cm") == true)
        show(overlay, vectors: [height, distance], showImperial: false)
        XCTAssertTrue(overlay.subviews.compactMap { $0 as? UILabel }.contains { $0 === heightLabel })
        XCTAssertTrue(heightLabel.text?.contains("40.0 cm") == true)
        XCTAssertFalse(heightLabel.text?.contains(" ft ") == true)
        XCTAssertFalse(heightLabel.accessibilityValue?.contains(" ft ") == true)
        XCTAssertTrue(overlay.bounds.contains(heightLabel.frame))
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: height.dictionary, options: [.sortedKeys]), original)
    }

    func testPendingCandidateRemainsProvisionalUntilConfirmedAndReusesItsRenderSlot() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(origin: .zero, size: size))
        show(overlay, planes: [plane()], pendingFloor: "floor-A")
        let label = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first)
        let shape = try XCTUnwrap(overlay.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        XCTAssertEqual(label.accessibilityLabel, "Selected floor candidate")
        XCTAssertTrue(label.accessibilityValue?.lowercased().contains("provisional") == true)
        XCTAssertTrue(label.accessibilityValue?.contains("Done") == true)
        XCTAssertNotNil(shape.lineDashPattern)
        XCTAssertEqual(overlay.floorPlaneID(at: CGPoint(x: 100, y: 100)), "floor-A")
        show(overlay, planes: [plane()], selected: "floor-A")
        XCTAssertTrue(overlay.subviews.compactMap { $0 as? UILabel }.first === label)
        XCTAssertEqual(label.accessibilityLabel, "Floor selected")
        XCTAssertNil(shape.lineDashPattern)
    }
}
