import Foundation
import XCTest

/// Measurements can predate the first accepted recording frame. Replay must
/// retain that initial history and reconstruct later edits after backward seeks.
final class RecordingPlaybackMeasurementHistoryTests: XCTestCase {
    private let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    private let intrinsics: [Double] = [100,0,0, 0,100,0, 50,50,1]

    private func frame(_ index: Int) -> [String: Any] {
        let pts = Double(index) / 10
        return ["frameId": "f\(index)", "segmentId": "A", "timestamp": 1000 + pts,
                "videoPTSSeconds": pts, "videoAppended": true, "tracking": "normal",
                "imageWidth": 100, "imageHeight": 100, "cameraToWorldColumnMajor": identity,
                "intrinsicsColumnMajor": intrinsics]
    }

    private func measurement(_ id: String, timestamp: Double, y: Double) -> [String: Any] {
        ["id": id, "kind": "distance", "segmentId": "A", "timestamp": timestamp,
         "startWorldMeters": [-0.3, y, -2], "endWorldMeters": [0.3, y + 0.2, -2],
         "distanceMeters": hypot(0.6, 0.2), "verticalMeters": 0.2, "sourcePoints": []]
    }

    func testInitialMeasurementsSurviveFirstFrameAndSeekingThroughCompletionAndClear() throws {
        let baseline = measurement("before-recording", timestamp: 999.5, y: 0)
        let added = measurement("during-recording", timestamp: 1000.15, y: 0.3)
        let beforeFirstFrame = 1000.0 - 1.0 / 30
        let events: [[String: Any]] = [
            ["type": "segment", "segmentId": "A", "timestamp": beforeFirstFrame],
            ["type": "debugSettingsAtStart", "timestamp": beforeFirstFrame, "settings": [:]],
            ["type": "measurementsAtStart", "segmentId": "A", "timestamp": beforeFirstFrame,
             "measurements": [baseline], "floor": NSNull()],
            ["type": "measurementCompleted", "segmentId": "A", "timestamp": 1000.15, "measurement": added],
            ["type": "measurementsCleared", "segmentId": "A", "timestamp": 1000.35],
        ]
        let timeline = try RecordingPlaybackTimeline(
            manifest: ["schemaVersion": 1, "finalized": true, "firstARFrameTimestamp": 1000.0],
            frames: (0...5).map(frame), events: events)

        func identifiers(at seconds: Double) throws -> Set<String> {
            Set(try XCTUnwrap(timeline.snapshot(at: seconds)).lines.map(\.id))
        }
        let initial: Set<String> = ["measurement.before-recording", "measurement.before-recording.horizontal", "measurement.before-recording.vertical"]
        let both = initial.union(["measurement.during-recording", "measurement.during-recording.horizontal", "measurement.during-recording.vertical"])
        XCTAssertEqual(try identifiers(at: 0), initial)
        XCTAssertEqual(try identifiers(at: 0.1), initial)
        XCTAssertEqual(try identifiers(at: 0.25), both)
        XCTAssertTrue(try identifiers(at: 0.4).isEmpty)
        XCTAssertEqual(try identifiers(at: 0.25), both)
        XCTAssertEqual(try identifiers(at: 0), initial)
        XCTAssertTrue(try identifiers(at: 0.5).isEmpty)
    }
}
