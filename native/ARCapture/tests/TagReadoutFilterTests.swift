import XCTest

final class TagReadoutFilterTests: XCTestCase {
    private func row(id: Int = 42, height: Double = 1, lidar: Double = 2, tag: Double = 2.2,
                     source: String = "sceneDepth", floor: String = "floor-A", segment: String = "segment-A") -> [String: Any] {
        let heightRecord: [String: Any] = ["available": true, "meters": height, "source": source,
            "floorId": floor, "segmentId": segment, "worldMeters": [0, height, 0],
            "floorFootWorldMeters": [0, 0, 0]]
        let ranges: [String: Any] = ["lidarAvailable": true, "tagAvailable": true,
            "lidarRangeMeters": lidar, "tagRangeMeters": tag, "distanceDeltaMeters": abs(lidar-tag),
            "lidarDepthZMeters": 1.8, "tagDepthZMeters": 2.0, "segmentId": segment]
        return ["id": id, "corners": [[1, 2], [3, 4]], "pose": ["translation": [0, 0, tag]],
            "floorHeight": heightRecord, "cameraRanges": ranges,
            "debug": ["floorHeight": heightRecord, "cameraRanges": ranges, "severity": "warning",
                      "depthDifferenceMeters": 0.2, "translationMeters": [0, 0, tag]]]
    }
    private func value(_ row: [String: Any], _ dictionary: String = "floorHeight", _ key: String = "meters") -> Double {
        ((row[dictionary] as? [String: Any])?[key] as? NSNumber)?.doubleValue ?? .nan
    }
    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private func filtered(_ filter: inout TagReadoutFilter, _ row: [String: Any], frame: Int,
                          samples: Int = 5) -> [String: Any] {
        filter.apply(to: [row], timestamp: 10 + Double(frame)/30, enabled: true, samples: samples)[0]
    }

    func testDisabledIsExactPassthroughAndClearsHistory() throws {
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        let input = [row(height: 4)]
        let disabled = filter.apply(to: input, timestamp: 10.1, enabled: false, samples: 5)
        XCTAssertEqual(try json(disabled), try json(input))
        XCTAssertEqual(value(filtered(&filter, row(height: 8), frame: 4)), 8)
    }

    func testFirstSampleHasNoWarmupLagAndInputGeometryIsUntouched() throws {
        var filter = TagReadoutFilter()
        let original = row()
        let result = filtered(&filter, original, frame: 0)
        XCTAssertEqual(value(result), 1)
        XCTAssertEqual(value(result, "floorHeight", "rawMeters"), 1)
        _ = filtered(&filter, row(height: 1.6), frame: 1)
        let output = filtered(&filter, row(height: 1.6, lidar: 3, tag: 4), frame: 2)
        XCTAssertLessThan(value(output), 1.6)
        XCTAssertEqual(try json(original), try json(row()), "Input/recording dictionaries must remain raw")
        for key in ["corners", "pose"] {
            XCTAssertEqual(try json(output[key]!), try json(row(height: 1.6, lidar: 3, tag: 4)[key]!))
        }
        let height = try XCTUnwrap(output["floorHeight"] as? [String: Any])
        XCTAssertEqual(height["worldMeters"] as? [Double], [0, 1.6, 0])
        let debug = try XCTUnwrap(output["debug"] as? [String: Any])
        XCTAssertEqual(debug["severity"] as? String, "warning")
        XCTAssertEqual(debug["depthDifferenceMeters"] as? Double, 0.2)
        XCTAssertEqual(try json(debug["floorHeight"]!), try json(output["floorHeight"]!))
        XCTAssertEqual(try json(debug["cameraRanges"]!), try json(output["cameraRanges"]!))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(output))
    }

    func testNominalKalmanGainAndDisplayedDeltaAreConsistent() throws {
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        let result = filtered(&filter, row(height: 1.6, lidar: 3, tag: 4), frame: 1)
        XCTAssertEqual(value(result), 1.2, accuracy: 1e-12)
        let lidar = value(result, "cameraRanges", "lidarRangeMeters")
        let tag = value(result, "cameraRanges", "tagRangeMeters")
        XCTAssertEqual(lidar, 2 + 1.0/3, accuracy: 1e-12)
        XCTAssertEqual(value(result, "cameraRanges", "distanceDeltaMeters"), abs(lidar-tag), accuracy: 1e-12)
        XCTAssertEqual(value(result, "cameraRanges", "rawDistanceDeltaMeters"), 1)
        XCTAssertEqual(value(result, "cameraRanges", "lidarDepthZMeters"), 1.8)
    }

    func testJitterIsReducedAndHigherSampleStrengthAddsLag() {
        var filter = TagReadoutFilter()
        var rawSquaredError = 0.0, filteredSquaredError = 0.0
        for frame in 0..<90 {
            let raw = 1 + (frame.isMultiple(of: 2) ? 0.1 : -0.1)
            let result = filtered(&filter, row(height: raw), frame: frame)
            if frame >= 20 {
                rawSquaredError += pow(raw-1, 2)
                filteredSquaredError += pow(value(result)-1, 2)
            }
        }
        XCTAssertLessThan(filteredSquaredError, rawSquaredError * 0.1)
        var light = TagReadoutFilter(), strong = TagReadoutFilter()
        _ = filtered(&light, row(), frame: 0, samples: 3)
        _ = filtered(&strong, row(), frame: 0, samples: 30)
        let lightStep = value(filtered(&light, row(height: 2), frame: 1, samples: 3))
        let strongStep = value(filtered(&strong, row(height: 2), frame: 1, samples: 30))
        XCTAssertGreaterThan(lightStep, strongStep)
        XCTAssertGreaterThan(strongStep, 1)
        XCTAssertLessThan(lightStep, 2)
    }

    func testElapsedFrameTimeIncreasesResponsivenessAfterDroppedFrames() {
        var normal = TagReadoutFilter(), dropped = TagReadoutFilter()
        _ = filtered(&normal, row(), frame: 0)
        _ = filtered(&dropped, row(), frame: 0)
        let normalValue = value(filtered(&normal, row(height: 2), frame: 1))
        let droppedValue = value(filtered(&dropped, row(height: 2), frame: 2))
        XCTAssertGreaterThan(droppedValue, normalValue)
    }

    func testTagsAndRangeChannelsHaveIndependentHistories() {
        var filter = TagReadoutFilter()
        _ = filter.apply(to: [row(id: 1, height: 1), row(id: 2, height: 10)], timestamp: 10, enabled: true, samples: 5)
        let output = filter.apply(to: [row(id: 2, height: 13, lidar: 9, tag: 6),
                                      row(id: 1, height: 4, lidar: 3, tag: 4)],
                                  timestamp: 10 + 1.0/30, enabled: true, samples: 5)
        XCTAssertEqual(value(output[0]), 11, accuracy: 1e-12)
        XCTAssertEqual(value(output[1]), 2, accuracy: 1e-12)
        XCTAssertEqual(value(output[0], "cameraRanges", "lidarRangeMeters"), 2 + 7.0/3, accuracy: 1e-12)
        XCTAssertEqual(value(output[1], "cameraRanges", "lidarRangeMeters"), 2 + 1.0/3, accuracy: 1e-12)
    }

    func testDisappearedTagsAndUnavailableSignalsRestartImmediately() throws {
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        _ = filter.apply(to: [], timestamp: 10 + 1.0/30, enabled: true, samples: 5)
        XCTAssertEqual(value(filtered(&filter, row(height: 4), frame: 2)), 4)
        var unavailable = row(height: 4)
        unavailable["floorHeight"] = ["available": false, "meters": NSNull(), "reason": "missingDepth"]
        unavailable["cameraRanges"] = ["lidarAvailable": false, "lidarRangeMeters": NSNull(),
            "tagAvailable": true, "tagRangeMeters": 2.2, "distanceDeltaMeters": NSNull()]
        let result = filtered(&filter, unavailable, frame: 3)
        XCTAssertTrue((result["floorHeight"] as? [String: Any])?["meters"] is NSNull)
        XCTAssertTrue((result["cameraRanges"] as? [String: Any])?["distanceDeltaMeters"] is NSNull)
        let returned = filtered(&filter, row(height: 8, lidar: 9), frame: 4)
        XCTAssertEqual(value(returned), 8)
        XCTAssertEqual(value(returned, "cameraRanges", "lidarRangeMeters"), 9)
    }

    func testHeightSourceFloorAndSegmentChangesStartNewEstimates() {
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        XCTAssertEqual(value(filtered(&filter, row(height: 4, source: "tagPose"), frame: 1)), 4)
        XCTAssertEqual(value(filtered(&filter, row(height: 7, source: "tagPose", floor: "floor-B"), frame: 2)), 7)
        let changedSegment = filtered(&filter, row(height: 9, lidar: 11, segment: "segment-B"), frame: 3)
        XCTAssertEqual(value(changedSegment), 9)
        XCTAssertEqual(value(changedSegment, "cameraRanges", "lidarRangeMeters"), 11)
    }

    func testLongGapsSettingChangesAndExplicitResetClearHistory() {
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        XCTAssertEqual(value(filtered(&filter, row(height: 4), frame: 20)), 4)
        XCTAssertEqual(value(filtered(&filter, row(height: 7), frame: 21, samples: 10)), 7)
        filter.reset()
        XCTAssertEqual(value(filtered(&filter, row(height: 9), frame: 22, samples: 10)), 9)
    }

    func testBadTimestampsAndUnsupportedSettingsPassThroughAndReset() throws {
        for timestamp in [10.0, 9.0, Double.nan, Double.infinity] {
            var filter = TagReadoutFilter()
            _ = filtered(&filter, row(), frame: 0)
            let input = [row(height: 4)]
            let output = filter.apply(to: input, timestamp: timestamp, enabled: true, samples: 5)
            XCTAssertEqual(try json(output), try json(input))
            XCTAssertEqual(value(filtered(&filter, row(height: 7), frame: 1)), 7)
        }
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        let input = [row(height: 4)]
        XCTAssertEqual(try json(filter.apply(to: input, timestamp: 10.1, enabled: true, samples: 4)), try json(input))
    }

    func testInvalidScalarsAndMalformedAvailabilityNeverReuseAnOldEstimate() {
        for invalid in [Double.nan, Double.infinity, -1.0, true, NSNull(), "3"] as [Any] {
            var filter = TagReadoutFilter()
            _ = filtered(&filter, row(), frame: 0)
            var invalidRow = row()
            invalidRow["floorHeight"] = ["available": true, "meters": invalid]
            invalidRow["cameraRanges"] = ["lidarAvailable": true, "lidarRangeMeters": invalid,
                "tagAvailable": false, "tagRangeMeters": NSNull(), "distanceDeltaMeters": NSNull()]
            let output = filtered(&filter, invalidRow, frame: 1)
            XCTAssertNil(output["readoutFilter"])
            let returned = filtered(&filter, row(height: 7, lidar: 8), frame: 2)
            XCTAssertEqual(value(returned), 7)
            XCTAssertEqual(value(returned, "cameraRanges", "lidarRangeMeters"), 8)
        }
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        var invalid = row()
        invalid["floorHeight"] = ["available": 1, "meters": 4]
        let output = filtered(&filter, invalid, frame: 1)
        XCTAssertEqual(value(output), 4)
        XCTAssertNil((output["floorHeight"] as? [String: Any])?["readoutFilter"])
    }

    func testDuplicateTagIdsPassThroughWithoutCombiningObservations() throws {
        var filter = TagReadoutFilter()
        _ = filtered(&filter, row(), frame: 0)
        let input = [row(height: 4), row(height: 8)]
        let output = filter.apply(to: input, timestamp: 10 + 1.0/30, enabled: true, samples: 5)
        XCTAssertEqual(try json(output), try json(input))
        XCTAssertEqual(value(filtered(&filter, row(height: 9), frame: 2)), 9)
    }
}
