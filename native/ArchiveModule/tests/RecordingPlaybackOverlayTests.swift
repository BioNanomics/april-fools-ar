import AVFoundation
import AVKit
import CoreGraphics
import CoreVideo
import CryptoKit
import UIKit
import XCTest

/// Synthetic recording metadata exercises recorded-time state, rather than a
/// live camera or the host clock. These are not sensor-accuracy tests.
final class RecordingPlaybackTimelineTests: XCTestCase {
    private let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    private let intrinsics: [Double] = [100, 0, 0, 0, 100, 0, 50, 50, 1]

    private var manifest: [String: Any] {
        ["schemaVersion": 1, "finalized": true, "firstARFrameTimestamp": 1000.0,
         "videoContent": ["playbackTransform": [1, 0, 0, 1, 0, 0], "overlaysBurnedIn": false]]
    }

    private func frame(_ id: String, _ pts: Double, x: Double = 0, segment: String = "A",
                       accepted: Bool = true, tracking: String = "normal") -> [String: Any] {
        var pose = identity
        pose[12] = x
        return ["frameId": id, "segmentId": segment, "timestamp": 1000 + pts,
                "videoPTSSeconds": pts, "videoAppended": accepted,
                "tracking": tracking, "imageWidth": 100, "imageHeight": 100,
                "intrinsicsColumnMajor": intrinsics, "cameraToWorldColumnMajor": pose,
                "displayTransform": [1, 0, 0, 1, 0, 0],
                "previewDisplayTransform": [4, 0, 0, 4, -1.5, -1.5], "displayZoom": 4]
    }

    private func detection(frameID: String = "f0", pts: Double = 0,
                           includePose: Bool = true, empty: Bool = false, gravityOrientation: Any? = nil) -> [String: Any] {
        var tag: [String: Any] = ["id": 5, "family": "tag36h11",
                                  "corners": [[20, 20], [80, 20], [80, 80], [20, 80]],
                                  "debug": ["severity": "good", "valid": true]]
        tag["gravityOrientation"] = gravityOrientation
        if includePose {
            tag["pose"] = ["translation": [0, 0, 2],
                           "rotationRowMajor": [1, 0, 0, 0, 1, 0, 0, 0, 1], "tagSizeMeters": 1.2, "ambiguous": false]
        }
        return ["type": "aprilTagDetections", "frameId": frameID, "segmentId": "A",
                "timestamp": 1000 + pts, "analysisSucceeded": true,
                "imageWidth": 100, "imageHeight": 100,
                "intrinsicsColumnMajor": intrinsics, "cameraToWorldColumnMajor": identity,
                "displayTransform": [1, 0, 0, 1, 0, 0], "tracking": "normal",
                "detections": empty ? [] : [tag]]
    }

    private func measurementEvent(pts: Double = 0.1, start: [Double] = [-0.2, 0, -2],
                                  end: [Double] = [0.2, 0.2, -2], kind: String = "distance") -> [String: Any] {
        ["type": "measurementCompleted", "segmentId": "A", "timestamp": 1000 + pts,
         "measurement": ["id": "m1", "kind": kind, "segmentId": "A", "timestamp": 1000 + pts,
                         "startWorldMeters": start, "endWorldMeters": end,
                         "distanceMeters": sqrt(0.2), "verticalMeters": 0.2, "sourcePoints": []]]
    }

    func testUsesVideoPTSAndAcceptedFramesWithoutApplyingPreviewZoom() throws {
        let timeline = try RecordingPlaybackTimeline(manifest: manifest,
            frames: [frame("f0", 0), frame("omitted", 0.1, x: 100, accepted: false), frame("f1", 0.2, x: 0.2)],
            events: [detection()])
        let start = try XCTUnwrap(timeline.snapshot(at: 0))
        XCTAssertEqual(start.frameID, "f0")
        XCTAssertEqual(start.imageSize, CGSize(width: 100, height: 100))
        let firstTag = try XCTUnwrap(start.tags.first)
        XCTAssertEqual(firstTag.corners.count, 4)
        XCTAssertEqual(firstTag.corners[0].x, 20, accuracy: 1e-5)
        XCTAssertEqual(firstTag.corners[0].y, 20, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: 0.15)).frameID, "f0")
        XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: 0.25)).frameID, "f1")
        XCTAssertNil(timeline.snapshot(at: -.infinity))
        XCTAssertNil(timeline.snapshot(at: .nan))
    }

    func testReprojectsTagPlaneForCurrentMoviePoseAndDoesNotInventMissingPose() throws {
        let frames = [frame("f0", 0), frame("f1", 0.2, x: 0.2)]
        let tracked = try RecordingPlaybackTimeline(manifest: manifest, frames: frames, events: [detection()])
        let moved = try XCTUnwrap(try XCTUnwrap(tracked.snapshot(at: 0.2)).tags.first)
        // Moving the camera +0.2 m at z=2, fx=100, moves image X left by 10 px.
        XCTAssertEqual(moved.corners[0].x, 10, accuracy: 1e-4)
        XCTAssertEqual(moved.corners[0].y, 20, accuracy: 1e-4)
        let imageOnly = try RecordingPlaybackTimeline(manifest: manifest, frames: frames,
                                                     events: [detection(includePose: false)])
        XCTAssertEqual(try XCTUnwrap(imageOnly.snapshot(at: 0)).tags.count, 1)
        XCTAssertTrue(try XCTUnwrap(imageOnly.snapshot(at: 0.2)).tags.isEmpty)
    }

    func testEmptyAnalysisAndStaleDetectionsClearInRecordedTimeAfterSeeking() throws {
        let frames = [frame("f0", 0), frame("f1", 0.2), frame("f2", 0.6)]
        // Native detection can finish out of order. Source time remains authoritative.
        let outOfOrder = try RecordingPlaybackTimeline(manifest: manifest, frames: frames,
            events: [detection(frameID: "f1", pts: 0.2, empty: true), detection()])
        XCTAssertTrue(try XCTUnwrap(outOfOrder.snapshot(at: 0.2)).tags.isEmpty)
        XCTAssertEqual(try XCTUnwrap(outOfOrder.snapshot(at: 0)).tags.count, 1)
        XCTAssertTrue(try XCTUnwrap(outOfOrder.snapshot(at: 0.6)).tags.isEmpty)
        let stale = try RecordingPlaybackTimeline(manifest: manifest, frames: frames, events: [detection()])
        XCTAssertTrue(try XCTUnwrap(stale.snapshot(at: 0.6)).tags.isEmpty)
        XCTAssertEqual(try XCTUnwrap(stale.snapshot(at: 0)).tags.count, 1)
    }

    func testRecordedGravityOrientationSurvivesCameraMovementAndExpiresWithItsTag() throws {
        let orientation: [String: Any] = ["available": true, "reason": "valid", "tiltFromVerticalDegrees": 12.5,
                                          "twistDegrees": -3.2, "frameId": "f0", "segmentId": "A"]
        let timeline = try RecordingPlaybackTimeline(manifest: manifest,
            frames: [frame("f0", 0), frame("moved", 0.2, x: 0.2), frame("stale", 0.6), frame("next", 1, segment: "B")],
            events: [detection(gravityOrientation: orientation)])
        let first = try XCTUnwrap(try XCTUnwrap(timeline.snapshot(at: 0)).tags.first)
        let moved = try XCTUnwrap(try XCTUnwrap(timeline.snapshot(at: 0.2)).tags.first)
        XCTAssertTrue(first.label.contains("Lean 12.5° · Upright -3.2°"))
        XCTAssertEqual(moved.label, first.label, "Playback must use the recorded orientation, not the current movie camera")
        XCTAssertNotEqual(moved.corners[0].x, first.corners[0].x)
        XCTAssertTrue(try XCTUnwrap(timeline.snapshot(at: 0.6)).tags.isEmpty)
        XCTAssertTrue(try XCTUnwrap(timeline.snapshot(at: 1)).tags.isEmpty)
        XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(timeline.snapshot(at: 0)).tags.first).label, first.label)
    }

    func testRecordedGravityOrientationDisplaysZeroHorizontalAndSignedValues() throws {
        let cases: [(Double, Any, String)] = [
            (0, 0.0, "Lean 0.0° · Upright +0.0°"),
            (90, NSNull(), "Lean 90.0° · Upright —"),
            (45, 180.0, "Lean 45.0° · Upright +180.0°"),
            (12.5, -180.0, "Lean 12.5° · Upright -180.0°"),
        ]
        for (tilt, twist, expected) in cases {
            let orientation: [String: Any] = ["available": true, "reason": "valid", "tiltFromVerticalDegrees": tilt, "twistDegrees": twist]
            let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0)],
                                                         events: [detection(gravityOrientation: orientation)])
            XCTAssertTrue(try XCTUnwrap(try XCTUnwrap(timeline.snapshot(at: 0)).tags.first).label.contains(expected))
        }
    }

    func testCanonicalRecordedLeanAndUprightNamesTakePriorityOverLegacyAliases() throws {
        let orientation: [String: Any] = ["available": true, "reason": "valid",
            "planeLeanFromVerticalDegrees": 7.5, "uprightRotationClockwiseDegrees": -9.0,
            "tiltFromVerticalDegrees": 88.0, "twistDegrees": 44.0]
        let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0)],
                                                     events: [detection(gravityOrientation: orientation)])
        let label = try XCTUnwrap(try XCTUnwrap(timeline.snapshot(at: 0)).tags.first).label
        XCTAssertTrue(label.contains("Lean 7.5° · Upright -9.0°"))
        XCTAssertFalse(label.contains("88.0°"))
        XCTAssertFalse(label.contains("44.0°"))
    }

    func testRecordedGravityOrientationRejectsMalformedLegacyAndMismatchedValues() throws {
        func label(_ orientation: Any?) throws -> String {
            let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0)],
                                                         events: [detection(gravityOrientation: orientation)])
            return try XCTUnwrap(try XCTUnwrap(timeline.snapshot(at: 0)).tags.first).label
        }
        let valid: [String: Any] = ["available": true, "reason": "valid", "tiltFromVerticalDegrees": 12.5, "twistDegrees": 3.0]
        for missing: Any? in [nil, NSNull(), "unavailable"] {
            XCTAssertTrue(try label(missing).contains("Lean — · Upright —"), "Legacy recordings must not recalculate orientation")
        }
        for unavailable: Any in [false, 1, "true", NSNull()] {
            var orientation = valid; orientation["available"] = unavailable
            XCTAssertTrue(try label(orientation).contains("Lean — · Upright —"))
        }
        for tilt: Any in [true, "12.5", Double.nan, Double.infinity, -0.1, 90.1, NSNull()] {
            var orientation = valid; orientation["tiltFromVerticalDegrees"] = tilt
            XCTAssertTrue(try label(orientation).contains("Lean — · Upright —"))
        }
        for twist: Any? in [true, "3.0", Double.nan, Double.infinity, -180.1, 180.1, NSNull(), nil] {
            var orientation = valid; orientation["twistDegrees"] = twist
            XCTAssertTrue(try label(orientation).contains("Lean 12.5° · Upright —"))
        }
        for (key, value): (String, Any) in [("frameId", "other"), ("segmentId", "B"), ("frameId", NSNull()), ("segmentId", 1)] {
            var orientation = valid; orientation[key] = value
            XCTAssertTrue(try label(orientation).contains("Lean — · Upright —"))
        }
    }

    func testMeasurementsRespectClearSegmentTrackingAndBackwardSeek() throws {
        let clear: [String: Any] = ["type": "measurementsCleared", "segmentId": "A", "timestamp": 1000.3]
        let frames = [frame("f0", 0), frame("f1", 0.2), frame("f2", 0.4),
                      frame("f3", 0.6, tracking: "limited"), frame("f4", 1, segment: "B")]
        let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: frames,
                                                     events: [measurementEvent(), clear])
        XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: 0.2)).lines.count, 3)
        XCTAssertTrue(try XCTUnwrap(timeline.snapshot(at: 0.4)).lines.isEmpty)
        XCTAssertTrue(try XCTUnwrap(timeline.snapshot(at: 1)).lines.isEmpty)
        XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: 0.2)).lines.count, 3)
        let withoutClear = try RecordingPlaybackTimeline(manifest: manifest, frames: frames,
                                                         events: [measurementEvent()])
        XCTAssertTrue(try XCTUnwrap(withoutClear.snapshot(at: 0.6)).lines.isEmpty)
        XCTAssertTrue(try XCTUnwrap(withoutClear.snapshot(at: 1)).lines.isEmpty)
    }

    func testOmittedTrackingRecoveryCannotEnableLimitedDisplayedVideoFrame() throws {
        let frames = [frame("f0", 0), frame("limited", 0.2, tracking: "limited"),
                      frame("omitted", 0.3, accepted: false), frame("recovered", 0.4)]
        let tracking: [String: Any] = ["type": "trackingChanged", "segmentId": "A", "frameId": "omitted",
                                       "timestamp": 1000.3, "tracking": "normal"]
        let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: frames,
                                                     events: [measurementEvent(), tracking])
        let limited = try XCTUnwrap(timeline.snapshot(at: 0.35))
        XCTAssertEqual(limited.frameID, "limited")
        XCTAssertTrue(limited.lines.isEmpty)
        XCTAssertTrue(limited.message?.contains("limited") == true)
        XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: 0.4)).lines.count, 3)
    }

    func testDistanceTriangleUsesSavedEndpointsAndReprojectsEveryEdge() throws {
        let timeline = try RecordingPlaybackTimeline(manifest: manifest,
            frames: [frame("f0", 0), frame("f1", 0.2), frame("moved", 0.3, x: 0.2)], events: [measurementEvent()])
        let before = Dictionary(uniqueKeysWithValues: try XCTUnwrap(timeline.snapshot(at: 0.2)).lines.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: try XCTUnwrap(timeline.snapshot(at: 0.3)).lines.map { ($0.id, $0) })
        XCTAssertEqual(Set(before.keys), ["measurement.m1", "measurement.m1.horizontal", "measurement.m1.vertical"])
        XCTAssertEqual(before["measurement.m1"]?.label, "D 0.447 m")
        XCTAssertEqual(before["measurement.m1.horizontal"]?.label, "H 0.400 m")
        XCTAssertEqual(before["measurement.m1.vertical"]?.label, "V +0.200 m")
        XCTAssertEqual(before["measurement.m1.horizontal"]?.style, "distance-horizontal")
        XCTAssertEqual(before["measurement.m1.vertical"]?.style, "distance-vertical")
        let direct = try XCTUnwrap(before["measurement.m1"])
        XCTAssertTrue(direct.accessibilityLabel?.contains("Horizontal 0.400 meters") == true)
        XCTAssertTrue(direct.accessibilityLabel?.contains("Vertical difference +0.200 meters") == true)
        let horizontal = try XCTUnwrap(before["measurement.m1.horizontal"])
        let vertical = try XCTUnwrap(before["measurement.m1.vertical"])
        XCTAssertEqual(horizontal.points[0].y, horizontal.points[1].y, accuracy: 1e-5)
        XCTAssertEqual(vertical.points[0].x, vertical.points[1].x, accuracy: 1e-5)
        XCTAssertEqual(horizontal.points[1], vertical.points[0])
        for (id, line) in before {
            let moved = try XCTUnwrap(after[id])
            XCTAssertEqual(moved.label, line.label)
            for index in line.points.indices {
                XCTAssertEqual(moved.points[index].x, line.points[index].x - 10, accuracy: 1e-4)
                XCTAssertEqual(moved.points[index].y, line.points[index].y, accuracy: 1e-4)
            }
        }
    }

    func testDistanceTriangleClipsLegsIndependentlyOfInvisibleDiagonalAndNearPlane() throws {
        let outside = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0.2)],
            events: [measurementEvent(start: [-3, 0, -2], end: [0, 3, -2])])
        let legs = try XCTUnwrap(outside.snapshot(at: 0.2)).lines
        XCTAssertEqual(Set(legs.map(\.id)), ["measurement.m1.horizontal", "measurement.m1.vertical"])
        XCTAssertEqual(Set(legs.compactMap(\.label)), ["H 3.000 m", "V +3.000 m"], "Old recordings derive component lengths from endpoints")

        let crossing = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0.2)],
            events: [measurementEvent(start: [-0.2, 0, 0.2], end: [0.2, 0.2, -2])])
        let clipped = try XCTUnwrap(crossing.snapshot(at: 0.2)).lines
        XCTAssertEqual(clipped.count, 3)
        for line in legs + clipped {
            XCTAssertEqual(line.points.count, 2)
            for point in line.points {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                XCTAssertTrue((-1e-5...100.00001).contains(point.x))
                XCTAssertTrue((-1e-5...100.00001).contains(point.y))
            }
        }
    }

    func testDistanceTriangleDegenerateLegsKeepZeroValuesWithoutOverlappingHelpers() throws {
        let cases: [([Double], [Double], String)] = [
            ([-0.2, 0, -2], [0.2, 0, -2], "D 0.400 m · H 0.400 m · V +0.000 m"),
            ([0, 0.2, -2], [0, -0.2, -2], "D 0.400 m · H 0.000 m · V -0.400 m"),
            ([0, 0, -2], [0, 0, -2], "D 0.000 m · H 0.000 m · V +0.000 m"),
        ]
        for (start, end, expected) in cases {
            let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0.2)],
                events: [measurementEvent(start: start, end: end)])
            let lines = try XCTUnwrap(timeline.snapshot(at: 0.2)).lines
            XCTAssertEqual(lines.map(\.id), ["measurement.m1"])
            XCTAssertEqual(lines.first?.label, expected)
            XCTAssertTrue(lines.first?.accessibilityLabel?.contains("Horizontal") == true)
            XCTAssertTrue(lines.first?.accessibilityLabel?.contains("Vertical difference") == true)
        }
        let height = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0.2)],
            events: [measurementEvent(kind: "height")])
        let heightLines = try XCTUnwrap(height.snapshot(at: 0.2)).lines
        XCTAssertEqual(heightLines.map(\.id), ["measurement.m1"])
        XCTAssertEqual(heightLines.first?.style, "height")
        XCTAssertTrue(heightLines.first?.label?.hasPrefix("Height ") == true)
    }

    func testOtherAndMissingMeasurementKindsKeepLegacyDirectLineWithoutTriangle() throws {
        for kind: String? in ["tagWidth", "unknown", nil] {
            var event = measurementEvent(kind: kind ?? "distance")
            var record = try XCTUnwrap(event["measurement"] as? [String: Any])
            record["kind"] = kind
            event["measurement"] = record
            let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0.2)], events: [event])
            let lines = try XCTUnwrap(timeline.snapshot(at: 0.2)).lines
            XCTAssertEqual(lines.map(\.id), ["measurement.m1"])
            XCTAssertEqual(lines.first?.label, "0.447 m · ΔY 0.200 m")
            XCTAssertEqual(lines.first?.style, "distance")
        }
    }

    func testSettingsFloorAndTrackingChangesInvalidateHeldTagContext() throws {
        let frames = [frame("f0", 0), frame("f1", 0.2)]
        let boundaries: [[String: Any]] = [
            ["type": "settingsChanged", "segmentId": "A", "timestamp": 1000.15, "settings": ["showPoseAxes": true]],
            ["type": "floorConfirmed", "segmentId": "A", "timestamp": 1000.15, "floor": ["id": "different-floor"]],
            ["type": "trackingChanged", "segmentId": "A", "timestamp": 1000.15, "tracking": "limited"],
        ]
        for boundary in boundaries {
            let recovered: [String: Any] = ["type": "trackingChanged", "segmentId": "A", "timestamp": 1000.18, "tracking": "normal"]
            let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: frames,
                                                         events: [detection(), boundary, recovered])
            XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: 0)).tags.count, 1)
            XCTAssertTrue(try XCTUnwrap(timeline.snapshot(at: 0.2)).tags.isEmpty, "Context change must not relabel an old observation")
            XCTAssertEqual(try XCTUnwrap(timeline.snapshot(at: 0)).tags.count, 1)
        }
    }

    func testFolderLoaderChecksOriginalLogHashesAndRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let framesURL = folder.appendingPathComponent("frames.jsonl")
        let eventsURL = folder.appendingPathComponent("events.jsonl")
        var frameData = try JSONSerialization.data(withJSONObject: frame("f0", 0), options: [.sortedKeys])
        frameData.append(10)
        var eventData = try JSONSerialization.data(withJSONObject: detection(), options: [.sortedKeys])
        eventData.append(10)
        try frameData.write(to: framesURL)
        try eventData.write(to: eventsURL)
        func entry(_ path: String, _ data: Data) -> [String: Any] {
            ["path": path, "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
        }
        var savedManifest = manifest
        savedManifest["fileInventory"] = [entry("frames.jsonl", frameData), entry("events.jsonl", eventData)]
        try JSONSerialization.data(withJSONObject: savedManifest, options: [.sortedKeys])
            .write(to: folder.appendingPathComponent("manifest.json"))
        let loaded = try RecordingPlaybackTimeline.load(folderURL: folder)
        XCTAssertEqual(try XCTUnwrap(loaded.snapshot(at: 0)).tags.count, 1)

        var tampered = eventData
        let idRange = try XCTUnwrap(tampered.range(of: Data("\"id\":5".utf8)))
        tampered[idRange.upperBound - 1] = 54
        XCTAssertEqual(tampered.count, eventData.count)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: tampered))
        try tampered.write(to: eventsURL)
        XCTAssertThrowsError(try RecordingPlaybackTimeline.load(folderURL: folder))
        try eventData.write(to: eventsURL)

        let outside = root.appendingPathComponent("outside.jsonl")
        try frameData.write(to: outside)
        try FileManager.default.removeItem(at: framesURL)
        try FileManager.default.createSymbolicLink(at: framesURL, withDestinationURL: outside)
        XCTAssertThrowsError(try RecordingPlaybackTimeline.load(folderURL: folder))
    }

    func testMalformedFrameGeometryAndMissingTimeDoNotInventOverlayCoordinates() throws {
        var invalid = frame("invalid", 0)
        invalid["timestamp"] = nil
        invalid["cameraToWorldColumnMajor"] = [1, 2, 3]
        invalid["intrinsicsColumnMajor"] = [Double.nan]
        do {
            let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: [invalid], events: [detection()])
            let snapshot = timeline.snapshot(at: 0)
            XCTAssertTrue(snapshot == nil || snapshot!.tags.isEmpty)
            XCTAssertTrue(snapshot == nil || snapshot!.lines.isEmpty)
        } catch {
            // No usable source frames may reject metadata and let the player
            // explicitly fall back to clean video.
        }
    }
}

@MainActor
final class RecordingPlaybackOverlayUIKitTests: XCTestCase {
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func visibleTagLabels(_ view: UIView) -> [UILabel] {
        descendants(view).compactMap { $0 as? UILabel }.filter { label in
            guard label.accessibilityIdentifier?.hasPrefix("recording.preview.tag.") == true else { return false }
            var ancestor: UIView? = label
            while let current = ancestor {
                if current.isHidden || current.alpha == 0 { return false }
                ancestor = current.superview
            }
            return true
        }
    }

    private func assertOverlayControlAvoidsNativeTopRow(_ control: UIControl, in view: UIView,
                                                       file: StaticString = #filePath, line: UInt = #line) {
        let frame = control.convert(control.bounds, to: view)
        XCTAssertGreaterThanOrEqual(frame.minY, view.safeAreaInsets.top + 54,
            "Overlay toggle must leave the native Close/AirPlay row available", file: file, line: line)
        for native in descendants(view).compactMap({ $0 as? UIControl }) where native !== control && !native.isHidden {
            let label = native.accessibilityLabel?.lowercased() ?? ""
            guard label.contains("airplay") || label == "close" || label == "done" else { continue }
            let reserved = native.convert(native.bounds, to: view)
            guard reserved.width > 0, reserved.height > 0 else { continue }
            XCTAssertFalse(frame.intersects(reserved), "Overlay toggle obstructs native \(label)", file: file, line: line)
        }
    }

    private func eventually(_ message: String, timeout: Double = 4, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate(), message)
    }

    private func seek(_ player: AVPlayer, seconds: Double) async {
        await withCheckedContinuation { continuation in
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }

    private func movie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 100, AVVideoHeightKey: 100,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var raw: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 100, 100, kCVPixelFormatType_32BGRA, nil, &raw), kCVReturnSuccess)
        let buffer = try XCTUnwrap(raw)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, 128, CVPixelBufferGetBytesPerRow(buffer) * 100) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for index in 0..<5 {
            try await eventually("Video writer accepts fixture frame") { input.isReadyForMoreMediaData }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 5)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func playerTimeline() throws -> RecordingPlaybackTimeline {
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let intrinsics: [Double] = [100, 0, 0, 0, 100, 0, 50, 50, 1]
        let frames: [[String: Any]] = (0..<5).map { index in
            ["frameId": "video-\(index)", "segmentId": "A", "timestamp": 1000 + Double(index) / 5,
             "videoPTSSeconds": Double(index) / 5, "videoAppended": true, "tracking": "normal",
             "imageWidth": 100, "imageHeight": 100, "intrinsicsColumnMajor": intrinsics,
             "cameraToWorldColumnMajor": identity, "displayTransform": [1, 0, 0, 1, 0, 0]]
        }
        let event: [String: Any] = [
            "type": "aprilTagDetections", "frameId": "video-0", "segmentId": "A", "timestamp": 1000.0,
            "analysisSucceeded": true, "tracking": "normal", "imageWidth": 100, "imageHeight": 100,
            "intrinsicsColumnMajor": intrinsics, "cameraToWorldColumnMajor": identity,
            "displayTransform": [1, 0, 0, 1, 0, 0],
            "detections": [["id": 5, "corners": [[20, 20], [80, 20], [80, 80], [20, 80]],
                            "debug": ["severity": "good", "valid": true],
                            "pose": ["translation": [0, 0, 2], "rotationRowMajor": [1, 0, 0, 0, 1, 0, 0, 0, 1], "tagSizeMeters": 1.2, "ambiguous": false]]],
        ]
        return try RecordingPlaybackTimeline(manifest: ["finalized": true, "firstARFrameTimestamp": 1000.0], frames: frames, events: [event])
    }

    func testRealPlayerPauseSeekToggleAndDismissalKeepRecordedOverlaysSynchronized() async throws {
        let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: movieURL) }
        try await movie(at: movieURL)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let presenter = UIViewController()
        defer { presenter.dismiss(animated: false) }
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let preview = RecordingPreview(presenterProvider: { presenter })
        var dismissed = false
        try preview.beginPreparation()
        try preview.present(asset: AVURLAsset(url: movieURL), timeline: playerTimeline()) { dismissed = true }
        let controller = try XCTUnwrap(presenter.presentedViewController as? AVPlayerViewController)
        let player = try XCTUnwrap(controller.player)
        try await eventually("Player fixture becomes ready") { player.currentItem?.status == .readyToPlay }
        // Wait for the presentation completion's automatic play before pausing.
        try await eventually("Player appears") { controller.view.window != nil && !controller.isBeingPresented }
        player.pause()
        await seek(player, seconds: 0.05)
        try await eventually("Source-frame tag is visible while paused") { !self.visibleTagLabels(controller.view).isEmpty }
        let overlay = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "recording.preview.overlays" })
        let toggle = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "recording.preview.overlay-toggle" } as? UIControl)
        XCTAssertEqual(toggle.accessibilityLabel, "Recorded overlays")
        XCTAssertEqual(toggle.accessibilityValue, "On")
        assertOverlayControlAvoidsNativeTopRow(toggle, in: controller.view)
        XCTAssertEqual(player.rate, 0)

        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Recorded tag overlay in native player"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = FileManager.default.temporaryDirectory.appendingPathComponent("recording-playback-overlays.png")
        try XCTUnwrap(image.pngData()).write(to: screenshot)
        print("PLAYBACK_OVERLAY_PNG \(screenshot.path)")

        toggle.sendActions(for: .touchUpInside)
        XCTAssertEqual(toggle.accessibilityValue, "Off")
        XCTAssertTrue(visibleTagLabels(controller.view).isEmpty)
        toggle.sendActions(for: .touchUpInside)
        try await eventually("Overlay toggle restores the recorded tag") { !self.visibleTagLabels(controller.view).isEmpty }
        await seek(player, seconds: 0.8)
        try await eventually("Seek clears expired detection") { self.visibleTagLabels(controller.view).isEmpty }
        await seek(player, seconds: 0.05)
        try await eventually("Backward seek restores earlier detection") { !self.visibleTagLabels(controller.view).isEmpty }
        try await Task.sleep(nanoseconds: 750_000_000)
        XCTAssertFalse(visibleTagLabels(controller.view).isEmpty, "Paused video must not use live wall-clock expiry")
        XCTAssertEqual(player.rate, 0)

        presenter.dismiss(animated: false)
        try await eventually("Dismissal settles preview ownership") { dismissed }
        XCTAssertNil(controller.player)
        XCTAssertNil(player.currentItem)
        XCTAssertEqual(player.rate, 0)
        XCTAssertTrue(overlay.window == nil || overlay.subviews.isEmpty)
        XCTAssertNoThrow(try preview.beginPreparation())
        preview.cancelPreparation()
    }

    func testMissingMetadataKeepsCleanVideoAndExplainsUnavailableOverlayControl() async throws {
        let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: movieURL) }
        try await movie(at: movieURL)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let presenter = UIViewController()
        defer { presenter.dismiss(animated: false); window.isHidden = true }
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        let preview = RecordingPreview(presenterProvider: { presenter })
        try preview.beginPreparation()
        try preview.present(asset: AVURLAsset(url: movieURL), overlayMessage: "Overlay metadata is missing") {}
        let controller = try XCTUnwrap(presenter.presentedViewController as? AVPlayerViewController)
        let toggle = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "recording.preview.overlay-toggle" } as? UIControl)
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertEqual(toggle.accessibilityValue, "Unavailable")
        XCTAssertNotNil(controller.player?.currentItem)
        XCTAssertTrue(visibleTagLabels(controller.view).isEmpty)
        XCTAssertTrue(descendants(controller.view).contains { $0.accessibilityLabel?.contains("Overlay metadata is missing") == true })
    }

    func testOptionalPrivateRecordingShowsRecordedOverlaysOnItsActualVideo() async throws {
        guard let folder = Bundle(for: Self.self).url(forResource: "recorded-fixture", withExtension: nil) else {
            throw XCTSkip("Pass private --recording-folder and --recording-video paths to the simulator runner.")
        }
        let timeline = try RecordingPlaybackTimeline.load(folderURL: folder)
        let asset = AVURLAsset(url: folder.appendingPathComponent("recording.mp4"))
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertTrue(duration.isFinite && duration > 0)
        let sample = try XCTUnwrap((0..<Int(ceil(min(duration, 60) * 30))).map { Double($0) / 30 }.first {
            timeline.snapshot(at: $0)?.tags.isEmpty == false
        }, "Private recording should contain a recorded tag observation")
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let presenter = UIViewController()
        defer { presenter.dismiss(animated: false); window.isHidden = true }
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        let preview = RecordingPreview(presenterProvider: { presenter })
        try preview.beginPreparation()
        try preview.present(asset: asset, timeline: timeline) {}
        let controller = try XCTUnwrap(presenter.presentedViewController as? AVPlayerViewController)
        let player = try XCTUnwrap(controller.player)
        try await eventually("Private movie becomes ready") { player.currentItem?.status == .readyToPlay }
        try await eventually("Private player is presented") { controller.view.window != nil && !controller.isBeingPresented }
        player.pause()
        await seek(player, seconds: sample)
        try await eventually("Actual recorded tag is overlaid on its source video") { !self.visibleTagLabels(controller.view).isEmpty }
        XCTAssertEqual(player.rate, 0)
        let toggle = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "recording.preview.overlay-toggle" } as? UIControl)
        assertOverlayControlAvoidsNativeTopRow(toggle, in: controller.view)
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Private recorded clip with recorded overlays"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = FileManager.default.temporaryDirectory.appendingPathComponent("recording-playback-overlays-private.png")
        try XCTUnwrap(image.pngData()).write(to: screenshot)
        print("PLAYBACK_OVERLAY_PNG \(screenshot.path)")
    }

    func testImageMappingUsesFullVideoRectAndAllQuarterTurns() throws {
        let image = CGSize(width: 640, height: 480)
        let identityRect = CGRect(x: 10, y: 20, width: 320, height: 240)
        let identity = try XCTUnwrap(RecordingPlaybackOverlayView.imagePoint(CGPoint(x: 160, y: 120),
            imageSize: image, naturalSize: image, preferredTransform: .identity, videoRect: identityRect))
        XCTAssertEqual(identity.x, 90, accuracy: 1e-6)
        XCTAssertEqual(identity.y, 80, accuracy: 1e-6)

        let portraitRect = CGRect(x: 87.5, y: 0, width: 225, height: 300)
        let clockwise = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 480, ty: 0)
        let topLeft = try XCTUnwrap(RecordingPlaybackOverlayView.imagePoint(.zero,
            imageSize: image, naturalSize: image, preferredTransform: clockwise, videoRect: portraitRect))
        XCTAssertEqual(topLeft.x, 312.5, accuracy: 1e-6)
        XCTAssertEqual(topLeft.y, 0, accuracy: 1e-6)
        let rotations: [(CGAffineTransform, CGPoint)] = [
            (.identity, CGPoint(x: 143.75, y: 75)),
            (clockwise, CGPoint(x: 256.25, y: 75)),
            (CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 640, ty: 480), CGPoint(x: 256.25, y: 225)),
            (CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 640), CGPoint(x: 143.75, y: 225)),
        ]
        for (transform, expected) in rotations {
            let mapped = try XCTUnwrap(RecordingPlaybackOverlayView.imagePoint(CGPoint(x: 160, y: 120),
                imageSize: image, naturalSize: image, preferredTransform: transform, videoRect: portraitRect))
            XCTAssertEqual(mapped.x, expected.x, accuracy: 1e-6)
            XCTAssertEqual(mapped.y, expected.y, accuracy: 1e-6)
        }
        XCTAssertNil(RecordingPlaybackOverlayView.imagePoint(.zero, imageSize: .zero,
            naturalSize: image, preferredTransform: .identity, videoRect: identityRect))
        XCTAssertNil(RecordingPlaybackOverlayView.imagePoint(CGPoint(x: CGFloat.nan, y: 0), imageSize: image,
            naturalSize: image, preferredTransform: .identity, videoRect: identityRect))
    }

    func testDistanceTriangleLabelsUseLegColorsAndCompleteDirectAccessibility() throws {
        let directAccessibility = "Distance 0.500 meters. Horizontal 0.400 meters. Vertical difference +0.300 meters."
        let snapshot = RecordingPlaybackSnapshot(imageSize: CGSize(width: 100, height: 100), frameID: "f0", segmentID: "A",
            tags: [], lines: [
                .init(id: "measurement.m1", points: [CGPoint(x: 20, y: 80), CGPoint(x: 80, y: 20)],
                      label: "D 0.500 m", style: "distance", accessibilityLabel: directAccessibility),
                .init(id: "measurement.m1.horizontal", points: [CGPoint(x: 20, y: 80), CGPoint(x: 80, y: 80)],
                      label: "H 0.400 m", style: "distance-horizontal"),
                .init(id: "measurement.m1.vertical", points: [CGPoint(x: 80, y: 80), CGPoint(x: 80, y: 20)],
                      label: "V +0.300 m", style: "distance-vertical"),
            ], polygons: [], message: nil)
        let view = RecordingPlaybackOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        view.show(snapshot: snapshot, videoRect: view.bounds, naturalSize: snapshot.imageSize, preferredTransform: .identity)
        let labels = descendants(view).compactMap { $0 as? UILabel }
        let direct = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "recording.preview.measurement.measurement.m1" })
        XCTAssertEqual(direct.accessibilityLabel, directAccessibility)
        XCTAssertEqual(direct.textColor, .systemYellow)
        XCTAssertEqual(labels.first { $0.text?.contains("H 0.400 m") == true }?.textColor, .systemCyan)
        XCTAssertEqual(labels.first { $0.text?.contains("V +0.300 m") == true }?.textColor, .systemOrange)
    }
}
