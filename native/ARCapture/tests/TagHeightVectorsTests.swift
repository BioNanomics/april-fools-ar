import XCTest
import UIKit
import simd

@MainActor
final class TagHeightVectorsTests: XCTestCase {
    private func floor(y: Float = -1, frameID: String = "floor-frame", timestamp: Double = 1) -> SpatialPlane {
        SpatialPlane(id: "floor", classification: "floor", origin: [0,y,-3], normal: [0,1,0],
            vertices: [[-2,y,-5],[2,y,-5],[2,y,-1],[-2,y,-1]], segmentID: "segment", frameID: frameID, timestamp: timestamp)
    }
    private func detection(floor: SpatialPlane, now: Double, meters: Double = 2) -> [String: Any] {
        var basis = floor.dictionary; basis["operatorConfirmed"] = true
        return ["id": 42, "floorHeight": ["available": true, "meters": meters, "source": "sceneDepth", "severity": "good",
            "frameId": "tag-frame", "segmentId": "segment", "timestamp": now,
            "floorId": floor.id, "floor": basis, "floorFootWorldMeters": [0.0,Double(floor.origin.y),-3.0],
            "worldMeters": [0.0,Double(floor.origin.y)+meters,-3.0]]]
    }
    private func vectors(_ rows: [[String: Any]], floor: SpatialPlane?, now: Double, tracking: String = "normal", mode: SpatialMode = .distance) -> [TagHeightVector] {
        TagHeightVectors.make(from: rows, floor: floor, segmentID: "segment", frameID: "tag-frame", tracking: tracking, mode: mode, now: now)
    }
    func testLiveVectorsReuseSourceWorldEndpointsAndPreserveDuplicateTagIDs() throws {
        let datum = floor(), now = ProcessInfo.processInfo.systemUptime
        let output = vectors([detection(floor: datum, now: now), detection(floor: datum, now: now, meters: 1)], floor: datum, now: now+0.1)
        XCTAssertEqual(output.count, 2); XCTAssertEqual(output.map(\.tagID), [42,42])
        XCTAssertEqual(output[0].start, SIMD3<Float>(0,-1,-3)); XCTAssertEqual(output[0].end, SIMD3<Float>(0,1,-3))
        XCTAssertEqual(output[0].midpoint, SIMD3<Float>(0,0,-3)); XCTAssertEqual(output[0].heightMeters, 2)
        XCTAssertEqual(output[1].midpoint, SIMD3<Float>(0,-0.5,-3))
    }
    func testFloorFrameTimestampLevelingAndSegmentMustMatchCurrentDatum() {
        let datum = floor(), now = ProcessInfo.processInfo.systemUptime, row = detection(floor: floor(), now: ProcessInfo.processInfo.systemUptime)
        for changed in [floor(frameID: "refined-frame"), floor(timestamp: 2), SpatialMeasurementMath.effectiveFloor(datum, levelWithGravity: true)] {
            XCTAssertTrue(vectors([row], floor: changed, now: now+0.1).isEmpty)
        }
        var bad = row, height = row["floorHeight"] as! [String: Any]
        height["segmentId"] = "another-segment"; bad["floorHeight"] = height
        XCTAssertTrue(vectors([bad], floor: datum, now: now+0.1).isEmpty)
        height["segmentId"] = "segment"; height["frameId"] = "other-camera-frame"; bad["floorHeight"] = height
        XCTAssertTrue(vectors([bad], floor: datum, now: now+0.1).isEmpty)
    }
    func testTrackingSetupTagWidthMissingFloorAndExpiredOrFutureSourcesHideVectors() {
        let datum = floor(), now = ProcessInfo.processInfo.systemUptime, row = detection(floor: floor(), now: ProcessInfo.processInfo.systemUptime)
        XCTAssertTrue(vectors([row], floor: nil, now: now+0.1).isEmpty)
        XCTAssertTrue(vectors([row], floor: datum, now: now+0.1, tracking: "limited").isEmpty)
        XCTAssertTrue(vectors([row], floor: datum, now: now+0.1, mode: .selectFloor).isEmpty)
        XCTAssertTrue(vectors([row], floor: datum, now: now+0.1, mode: .tagWidth).isEmpty)
        XCTAssertTrue(vectors([row], floor: datum, now: now+0.41).isEmpty)
        XCTAssertTrue(vectors([row], floor: datum, now: now-0.1).isEmpty)
    }
    func testMalformedAvailableEvidenceCannotCreateFloatingOrNonVerticalLines() {
        let datum = floor(), now = ProcessInfo.processInfo.systemUptime
        let changes: [[String: Any]] = [["available": 1], ["meters": true], ["meters": Double.nan], ["meters": 31.0],
            ["meters": 1.0], ["source": "invented"], ["worldMeters": [0.1,1.0,-3.0]],
            ["floorFootWorldMeters": [0.0,-0.5,-3.0], "worldMeters": [0.0,1.5,-3.0]]]
        for change in changes {
            var row = detection(floor: datum, now: now), height = row["floorHeight"] as! [String: Any]
            height.merge(change) { _, new in new }; row["floorHeight"] = height
            XCTAssertTrue(vectors([row], floor: datum, now: now+0.1).isEmpty)
        }
    }
    private var k: simd_float3x3 { simd_float3x3(columns: ([180,0,0],[0,180,0],[320,240,1])) }
    private func camera(_ transform: simd_float4x4, display: CGAffineTransform = .identity, viewport: CGSize) -> SpatialProjection.Camera {
        SpatialProjection.Camera(cameraToWorld: transform, intrinsics: k, imageSize: CGSize(width: 640,height: 480), displayTransform: display, viewportSize: viewport)!
    }
    private func show(_ overlay: SpatialMeasurementOverlayView, automatic: [TagHeightVector], manual: [SpatialMeasurement] = [], transform: simd_float4x4, display: CGAffineTransform = .identity, deadline: Double? = nil) {
        overlay.show(planes: [], measurements: manual, pendingPoints: [], selectedFloorID: "floor", isTrackingNormal: true,
            cameraToWorld: transform, intrinsics: k, imageSize: CGSize(width: 640,height: 480), displayTransform: display,
            expiresAt: deadline ?? ProcessInfo.processInfo.systemUptime+1, automaticTagHeights: automatic)
    }
    func testUIKitLabelsUseWorldMidpointUnderPerspectiveZoomAndCameraMovement() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(x:0,y:0,width:390,height:520))
        overlay.backgroundColor = .black
        let window = UIWindow(frame: overlay.bounds); window.rootViewController = UIViewController()
        window.rootViewController!.view.addSubview(overlay); window.makeKeyAndVisible()
        defer { overlay.clear(); window.isHidden = true }
        let now = ProcessInfo.processInfo.systemUptime, datum = floor()
        let vector = try XCTUnwrap(vectors([detection(floor: datum, now: now)], floor: datum, now: now).first)
        var transform = simd_float4x4(simd_quatf(angle: .pi/6, axis: [1,0,0]))
        show(overlay, automatic: [vector], transform: transform)
        let label = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "spatial.tagHeight.0.42" })
        let projection = camera(transform, viewport: overlay.bounds.size)
        let midpoint = try XCTUnwrap(projection.point(vector.midpoint)), ends = try XCTUnwrap(projection.segment(from: vector.start,to: vector.end))
        XCTAssertEqual(label.center.x, midpoint.x, accuracy: 0.01); XCTAssertEqual(label.center.y, midpoint.y, accuracy: 0.01)
        XCTAssertGreaterThan(abs(label.center.y-(ends[0].y+ends[1].y)/2), 5)
        XCTAssertEqual(label.font.pointSize, 11); XCTAssertFalse(label.isHidden)
        overlay.layoutIfNeeded(); CATransaction.flush()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("tag-height-vector-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(bounds: overlay.bounds).image { _ in overlay.drawHierarchy(in: overlay.bounds, afterScreenUpdates: true) }
        try XCTUnwrap(image.pngData()).write(to: path); print("OVERLAY_PNG=\(path.path)")
        transform.columns.3.x = 0.2
        let display = PreviewZoom.normalizedTransform(for: 1.2)
        show(overlay, automatic: [vector], transform: transform, display: display)
        let moved = try XCTUnwrap(camera(transform, display: display, viewport: overlay.bounds.size).point(vector.midpoint))
        XCTAssertEqual(label.center.x, moved.x, accuracy: 0.01); XCTAssertEqual(label.center.y, moved.y, accuracy: 0.01)
        XCTAssertTrue(overlay.subviews.compactMap { $0 as? UILabel }.contains { $0 === label })
    }
    func testAutomaticAndManualHeightMidpointsOffscreenStayHiddenWhileClippedLineRemains() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(x:0,y:0,width:390,height:520))
        defer { overlay.clear() }
        let now = ProcessInfo.processInfo.systemUptime, datum = floor(y: -15)
        let vector = try XCTUnwrap(vectors([detection(floor: datum, now: now, meters: 16)], floor: datum, now: now).first)
        let manual = SpatialMeasurement(id: "manual", kind: "height", start: vector.start, end: vector.end, segmentID: "segment", timestamp: now, sourcePoints: [], floor: datum)
        show(overlay, automatic: [vector], manual: [manual], transform: matrix_identity_float4x4)
        let labels = overlay.subviews.compactMap { $0 as? UILabel }.filter { $0.accessibilityIdentifier?.hasPrefix("spatial.tagHeight") == true || $0.accessibilityIdentifier == "spatial.measurement.manual" }
        XCTAssertEqual(labels.count, 2); XCTAssertTrue(labels.allSatisfy(\.isHidden))
        XCTAssertTrue(overlay.layer.sublayers!.compactMap { $0 as? CAShapeLayer }.contains { $0.path != nil })
    }
    func testSourceExpiryHidesAutomaticVectorsBeforeFreshCameraSceneDeadline() throws {
        let overlay = SpatialMeasurementOverlayView(frame: CGRect(x:0,y:0,width:390,height:520))
        defer { overlay.clear() }
        let now = ProcessInfo.processInfo.systemUptime, datum = floor()
        let vector = try XCTUnwrap(vectors([detection(floor: datum, now: now-0.3)], floor: datum, now: now).first)
        show(overlay, automatic: [vector], transform: matrix_identity_float4x4, deadline: now+1)
        let label = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "spatial.tagHeight.0.42" })
        let expired = expectation(description: "source expires separately from camera scene")
        DispatchQueue.main.asyncAfter(deadline: .now()+0.25) { XCTAssertTrue(label.isHidden); expired.fulfill() }
        wait(for: [expired], timeout: 1)
    }
}
