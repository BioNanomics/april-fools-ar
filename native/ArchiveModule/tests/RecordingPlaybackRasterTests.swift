import CryptoKit
import Foundation
import UIKit
import XCTest

final class RecordingPlaybackRasterTests: XCTestCase {
    private func frame(_ id: String, _ time: Double, mode: String? = nil, accepted: Bool = true, segment: String = "A") -> [String: Any] {
        var row: [String: Any] = ["frameId": id, "segmentId": segment, "timestamp": 1000+time,
                                 "videoPTSSeconds": time, "videoAppended": accepted, "tracking": "normal",
                                 "imageWidth": 100, "imageHeight": 100]
        row["previewMode"] = mode
        return row
    }
    private var manifest: [String: Any] { ["finalized": true, "firstARFrameTimestamp": 1000.0] }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func floats(_ values: [Float]) -> Data {
        var data = Data()
        for value in values {
            let bits = value.bitPattern
            data.append(contentsOf: [UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8),
                                     UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24)])
        }
        return data
    }
    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cg.dataProvider?.data)
        return Array(data as Data)
    }
    private func fixture(depthPath: String = "depth/f0.f32", bytes: Data? = nil,
                         declaredBytes: Int? = nil, sha: String? = nil) throws -> (URL, RecordingPlaybackTimeline) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("depth"), withIntermediateDirectories: true)
        let data = bytes ?? floats([0.0, 3.0, 6.0, .nan])
        try data.write(to: folder.appendingPathComponent("depth/f0.f32"))
        let confidence = Data([0, 1, 2, 255])
        try confidence.write(to: folder.appendingPathComponent("depth/f0.confidence.u8"))
        var meta = manifest
        meta["fileInventory"] = [
            ["path": depthPath, "bytes": declaredBytes ?? data.count, "sha256": sha ?? digest(data)],
            ["path": "depth/f0.confidence.u8", "bytes": confidence.count, "sha256": digest(confidence)],
        ]
        var source = frame("f0", 0, mode: "depth")
        source.merge(["depthPath": depthPath, "confidencePath": "depth/f0.confidence.u8",
                      "depthWidth": 2, "depthHeight": 2]) { _, new in new }
        return (folder, try RecordingPlaybackTimeline(manifest: meta, frames: [source], events: [], folderURL: folder))
    }

    func testRecordedModeFollowsDisplayedAcceptedFrameAndBackwardSeeking() throws {
        let timeline = try RecordingPlaybackTimeline(manifest: manifest, frames: [
            frame("f0", 0, mode: "camera"), frame("omitted", 0.1, mode: "confidence", accepted: false),
            frame("f1", 0.2, mode: "depth"), frame("f2", 0.4, mode: "confidence")], events: [])
        XCTAssertEqual(timeline.snapshot(at: 0.15)?.recordedPreviewMode, "camera")
        XCTAssertEqual(timeline.snapshot(at: 0.3)?.recordedPreviewMode, "depth")
        XCTAssertEqual(timeline.snapshot(at: 0.5)?.recordedPreviewMode, "confidence")
        XCTAssertEqual(timeline.snapshot(at: 0)?.recordedPreviewMode, "camera")
        let legacy = try RecordingPlaybackTimeline(manifest: manifest, frames: [frame("f0", 0)], events: [])
        XCTAssertNil(legacy.snapshot(at: 0)?.recordedPreviewMode)
    }

    func testRejectedVideoSampleMergesDimensionsAndNeverComesFromFutureOrAnotherSegment() throws {
        let data = floats([1, 2, 3, 4])
        var meta = manifest
        meta["fileInventory"] = [["path": "depth/f1.f32", "bytes": data.count, "sha256": digest(data)]]
        var omitted = frame("f1", 0.1, accepted: false)
        omitted["depthPath"] = "depth/f1.f32"
        let sampleEvent: [String: Any] = ["type": "bookmark", "frameId": "f1", "segmentId": "A",
                                        "timestamp": 1000.1, "depthPath": "depth/f1.f32", "depthWidth": 2, "depthHeight": 2]
        let timeline = try RecordingPlaybackTimeline(manifest: meta,
            frames: [frame("f0", 0), omitted, frame("f2", 0.2), frame("b0", 0.3, segment: "B")],
            events: [sampleEvent, ["type": "segment", "segmentId": "B", "timestamp": 1000.3]])
        XCTAssertTrue(timeline.hasDepthSamples)
        XCTAssertFalse(timeline.hasConfidenceSamples)
        XCTAssertNil(timeline.snapshot(at: 0.05)?.rasterSample)
        let sample = try XCTUnwrap(timeline.snapshot(at: 0.15)?.rasterSample)
        XCTAssertEqual(sample.imageSize, CGSize(width: 100, height: 100))
        XCTAssertEqual(sample.width, 2)
        XCTAssertEqual(timeline.snapshot(at: 0.25)?.rasterSample?.id, sample.id)
        XCTAssertNil(timeline.snapshot(at: 0.35)?.rasterSample)
        XCTAssertNil(timeline.snapshot(at: 0.05)?.rasterSample)
        let held = try RecordingPlaybackTimeline(manifest: meta, frames: [frame("f0", 0), omitted], events: [sampleEvent])
        XCTAssertNil(held.snapshot(at: 0.51)?.rasterSample)
    }

    func testDepthAndConfidencePalettesKeepSensorOrientationAndRejectInvalidValues() throws {
        let depth = try RecordingPlaybackRaster.image(data: floats([0, 3, 6, .nan, -.infinity, -1]), width: 3, height: 2, mode: "depth")
        XCTAssertEqual(depth.imageOrientation, .up)
        XCTAssertEqual(depth.size, CGSize(width: 3, height: 2))
        XCTAssertEqual(try pixels(depth), [0,0,0,255, 127,200,127,255, 0,0,255,255,
                                           0,0,0,255, 0,0,0,255, 0,0,0,255])
        let confidence = try RecordingPlaybackRaster.image(data: Data([0,1,2,3]), width: 2, height: 2, mode: "confidence")
        XCTAssertEqual(try pixels(confidence), [240,30,40,255, 240,220,40,255, 25,220,40,255, 0,0,0,255])
        XCTAssertThrowsError(try RecordingPlaybackRaster.image(data: Data([0]), width: 2, height: 2, mode: "depth"))
        XCTAssertThrowsError(try RecordingPlaybackRaster.image(data: Data(), width: Int.max, height: Int.max, mode: "depth"))
    }

    func testInventoryVerifiedMapsRenderAndTamperingFails() throws {
        let (folder, timeline) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sample = try XCTUnwrap(timeline.snapshot(at: 0)?.rasterSample)
        XCTAssertTrue(timeline.hasDepthSamples)
        XCTAssertTrue(timeline.hasConfidenceSamples)
        XCTAssertEqual(try pixels(timeline.rasterImage(for: sample, mode: "depth")).count, 16)
        XCTAssertEqual(try pixels(timeline.rasterImage(for: sample, mode: "confidence")).count, 16)
        try floats([1, 1, 1, 1]).write(to: folder.appendingPathComponent("depth/f0.f32"))
        XCTAssertThrowsError(try timeline.rasterImage(for: sample, mode: "depth"))
        XCTAssertThrowsError(try timeline.rasterImage(for: sample, mode: "camera"))
    }

    func testWrongInventorySizeAndTraversalNeverBecomeDepthSamples() throws {
        for (path, size) in [("depth/f0.f32", 15), ("depth/../f0.f32", 16), ("/depth/f0.f32", 16)] {
            let (folder, timeline) = try fixture(depthPath: path, declaredBytes: size)
            defer { try? FileManager.default.removeItem(at: folder) }
            XCTAssertFalse(timeline.hasDepthSamples)
        }
    }

    func testSymlinkedFileAndIntermediateDirectoryAreNotFollowed() throws {
        let (folder, timeline) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sample = try XCTUnwrap(timeline.snapshot(at: 0)?.rasterSample)
        let original = folder.appendingPathComponent("depth/f0.f32")
        let renamed = folder.appendingPathComponent("depth/real.f32")
        try FileManager.default.moveItem(at: original, to: renamed)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: renamed)
        XCTAssertThrowsError(try timeline.rasterImage(for: sample, mode: "depth"))
        try FileManager.default.removeItem(at: original)
        try FileManager.default.moveItem(at: renamed, to: original)
        let directory = folder.appendingPathComponent("depth")
        let realDirectory = folder.appendingPathComponent("real-depth")
        try FileManager.default.moveItem(at: directory, to: realDirectory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: realDirectory)
        XCTAssertThrowsError(try timeline.rasterImage(for: sample, mode: "depth"))
    }
}
