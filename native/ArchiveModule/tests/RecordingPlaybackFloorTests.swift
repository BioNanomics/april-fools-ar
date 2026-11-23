import CoreGraphics
import Foundation
import XCTest

/// Recorded floor provenance is independent of later datum/settings changes.
final class RecordingPlaybackFloorTests: XCTestCase {
    private let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    private let calibration: [Double] = [100,0,0, 0,100,0, 50,50,1]
    private var manifest: [String: Any] {
        ["schemaVersion": 1, "finalized": true, "firstARFrameTimestamp": 1000.0]
    }
    private func frame(_ index: Int) -> [String: Any] {
        let time = Double(index)/10
        return ["frameId": "f\(index)", "segmentId": "A", "timestamp": 1000+time,
                "videoPTSSeconds": time, "videoAppended": true, "tracking": "normal",
                "imageWidth": 100, "imageHeight": 100, "cameraToWorldColumnMajor": identity,
                "intrinsicsColumnMajor": calibration]
    }
    private func floor(level: Bool = false, tilted: Bool = false) -> [String: Any] {
        let slope = tilted && !level ? 0.1 : 0.0
        return ["id": "floor", "classification": "floor", "segmentId": "A", "frameId": "floor-frame",
                "timestamp": 999.0, "operatorConfirmed": true, "originWorldMeters": [0.0,-1.0,-3.0],
                "normalWorld": [0.0,1.0,slope], "observedNormalWorld": [0.0,1.0,tilted ? 0.1 : 0],
                "boundaryWorldMeters": [[-0.5,-1+slope,-4.0],[0.5,-1+slope,-4.0],
                                        [0.5,-1-slope,-2.0],[-0.5,-1-slope,-2.0]],
                "source": "ARPlaneAnchor+sceneDepth-plane-fit", "levelFloorWithGravity": level,
                "tiltSource": "sceneDepth-plane-fit", "tiltAvailable": true,
                "observedTiltDegrees": tilted ? 5.710593 : 0.0,
                "effectiveTiltDegrees": tilted && !level ? 5.710593 : 0.0, "floorFit": NSNull()]
    }
    private func baseline(_ floor: [String: Any]?) -> [String: Any] {
        ["type": "measurementsAtStart", "segmentId": "A", "timestamp": 999.9,
         "floor": floor as Any? ?? NSNull(), "measurements": []]
    }
    private func detection(_ index: Int, floor: [String: Any]) -> [String: Any] {
        let time = 1000+Double(index)/10
        var basis = floor
        basis.removeValue(forKey: "boundaryWorldMeters")
        basis.removeValue(forKey: "source")
        let height: [String: Any] = ["available": true, "meters": 2.0, "source": "sceneDepth", "reason": "valid",
            "floorId": "floor", "floor": basis, "frameId": "f\(index)", "segmentId": "A", "timestamp": time,
            "worldMeters": [0.0,1.0,-3.0], "floorFootWorldMeters": [0.0,-1.0,-3.0],
            "opticalMeters": [0.0,-1.0,3.0], "severity": "good"]
        let tag: [String: Any] = ["id": 5, "family": "tag36h11", "hamming": 0, "decisionMargin": 50.0,
            "center": [50.0,50.0-100.0/3.0],
            "corners": [[40.0,50.0-130.0/3.0],[60.0,50.0-130.0/3.0],
                        [60.0,50.0-70.0/3.0],[40.0,50.0-70.0/3.0]],
            "debug": ["valid": true, "status": "valid", "severity": "good"], "floorHeight": height,
            "pose": ["translation": [0.0,-1.0,3.0], "rotationRowMajor": [1,0,0,0,1,0,0,0,1],
                     "ambiguous": false, "tagSizeMeters": 0.6]]
        return ["type": "aprilTagDetections", "frameId": "f\(index)", "segmentId": "A", "timestamp": time,
                "analysisSucceeded": true, "detections": [tag], "floorSnapshot": floor,
                "imageWidth": 100, "imageHeight": 100, "cameraToWorldColumnMajor": identity,
                "intrinsicsColumnMajor": calibration, "tracking": "normal",
                "debugSettings": ["showImperialHeight": false, "showPoseAxes": false]]
    }
    private func changedHeight(_ event: [String: Any], _ update: ([String: Any]) -> [String: Any]) -> [String: Any] {
        var event = event, rows = event["detections"] as! [[String: Any]]
        rows[0]["floorHeight"] = update(rows[0]["floorHeight"] as! [String: Any])
        event["detections"] = rows
        return event
    }
    private func automatic(_ snapshot: RecordingPlaybackSnapshot) -> [RecordingPlaybackSnapshot.Line] {
        snapshot.lines.filter { $0.style == "tag-height" }
    }

    func testConfirmedFloorAndAutomaticHeightRequireMatchingRecordedProvenance() throws {
        let datum = floor(), event = detection(0, floor: floor())
        let good = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame(0)], events: [baseline(datum), event])
        let snapshot = try XCTUnwrap(good.snapshot(at: 0))
        XCTAssertEqual(snapshot.polygons.filter { $0.style == "floor" }.count, 1)
        XCTAssertEqual(automatic(snapshot).count, 1)
        XCTAssertTrue(try XCTUnwrap(automatic(snapshot).first?.label).contains("200.0 cm"))
        XCTAssertEqual(snapshot.polygons.filter { $0.style == "base" }.count, 1)
        let wrongTime = changedHeight(event) { var height = $0; height["timestamp"] = 1000.1; return height }
        let wrongFrame = changedHeight(event) { height in
            var height = height, basis = height["floor"] as! [String: Any]
            basis["frameId"] = "different-floor-frame"; height["floor"] = basis; return height
        }
        let wrongPlane = changedHeight(event) { height in
            var height = height, basis = height["floor"] as! [String: Any]
            basis["normalWorld"] = [0.0,1.0,0.1]; height["floor"] = basis; return height
        }
        for invalid in [wrongTime, wrongFrame, wrongPlane] {
            let model = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame(0)], events: [baseline(datum), invalid])
            XCTAssertTrue(automatic(try XCTUnwrap(model.snapshot(at: 0))).isEmpty)
        }
        let noFloor = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame(0)], events: [baseline(nil), event])
        XCTAssertTrue(automatic(try XCTUnwrap(noFloor.snapshot(at: 0))).isEmpty)
    }

    func testManualHeightKeepsItsOriginalFloorWhenCurrentFloorIsLeveled() throws {
        let original = floor(tilted: true), leveled = floor(level: true, tilted: true)
        let measurement: [String: Any] = ["id": "manual-height", "kind": "height", "segmentId": "A",
            "timestamp": 1000.05, "startWorldMeters": [0.0,-1.0,-3.0], "endWorldMeters": [0.0,1.0,-3.0],
            "distanceMeters": 2.0, "verticalMeters": 2.0, "heightMeters": 2.0, "horizontalMeters": 0.0,
            "sourcePoints": [], "floor": original]
        let model = try RecordingPlaybackTimeline(manifest: manifest, frames: (0...4).map(frame), events: [
            baseline(original),
            ["type": "measurementCompleted", "segmentId": "A", "timestamp": 1000.05, "measurement": measurement],
            ["type": "floorReferenceChanged", "segmentId": "A", "timestamp": 1000.2,
             "floor": leveled, "previousFloor": original, "levelFloorWithGravity": true]
        ])
        let before = try XCTUnwrap(model.snapshot(at: 0.1)), after = try XCTUnwrap(model.snapshot(at: 0.3))
        let beforeBase = try XCTUnwrap(before.polygons.first { $0.id == "measurement.manual-height.base" })
        let afterBase = try XCTUnwrap(after.polygons.first { $0.id == "measurement.manual-height.base" })
        XCTAssertEqual(beforeBase.points, afterBase.points, "Existing measurement base retains its original observed plane")
        XCTAssertEqual(before.lines.first { $0.style == "height" }?.points, after.lines.first { $0.style == "height" }?.points)
        XCTAssertEqual(before.lines.first { $0.style == "height" }?.label, after.lines.first { $0.style == "height" }?.label)
        XCTAssertTrue(before.polygons.contains { $0.style == "floorTilted" })
        XCTAssertTrue(after.polygons.contains { $0.style == "floor" })
        XCTAssertTrue(try XCTUnwrap(model.snapshot(at: 0.1)).polygons.contains { $0.style == "floorTilted" })
    }

    func testSettingsAndFloorConfirmationInvalidateOldDetectionsAndSeekRestoresHistory() throws {
        let original = floor(), leveled = floor(level: true)
        let first = detection(0, floor: original), second = detection(2, floor: original), fresh = detection(4, floor: leveled)
        let model = try RecordingPlaybackTimeline(manifest: manifest, frames: (0...5).map(frame), events: [
            baseline(original), first,
            ["type": "settingsChanged", "segmentId": "A", "timestamp": 1000.1,
             "settings": ["showPoseAxes": false, "showImperialHeight": false]],
            second,
            ["type": "floorConfirmed", "segmentId": "A", "timestamp": 1000.3, "floor": leveled],
            second, // A late analysis from before confirmation cannot revive the old floor.
            fresh
        ])
        XCTAssertEqual(automatic(try XCTUnwrap(model.snapshot(at: 0.05))).count, 1)
        XCTAssertTrue(try XCTUnwrap(model.snapshot(at: 0.15)).tags.isEmpty)
        XCTAssertEqual(automatic(try XCTUnwrap(model.snapshot(at: 0.25))).count, 1)
        let changed = try XCTUnwrap(model.snapshot(at: 0.35))
        XCTAssertTrue(changed.tags.isEmpty)
        XCTAssertTrue(automatic(changed).isEmpty)
        XCTAssertEqual(automatic(try XCTUnwrap(model.snapshot(at: 0.4))).count, 1)
        XCTAssertEqual(automatic(try XCTUnwrap(model.snapshot(at: 0.05))).count, 1)
        XCTAssertTrue(try XCTUnwrap(model.snapshot(at: 0.15)).tags.isEmpty)
    }
}
