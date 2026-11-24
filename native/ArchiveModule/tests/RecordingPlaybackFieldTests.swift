import CoreGraphics
import CryptoKit
import Foundation
import XCTest

/// Synthetic field metadata verifies recorded-time placement and transport. It
/// does not establish camera, LiDAR, or surveyed field accuracy.
final class RecordingPlaybackFieldTests: XCTestCase {
    private let identity: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    private let calibration: [Double] = [100,0,0, 0,100,0, 50,50,1]
    private let packageID = "fixture-field"
    private let packageHash = String(repeating: "a", count: 64)
    private var tagTransform: [Double] { [1,0,0,0, 0,-1,0,0, 0,0,-1,0, 0,0,-2,1] }
    private var definition: [String: Any] {
        ["schemaVersion": 1, "id": packageID, "tags": [
            ["id": 5, "family": "tag36h11", "poseSizeMeters": 1.2, "placement": "fixedField",
             "localizationEligible": true, "fieldFromTagColumnMajor": tagTransform],
            ["id": 6, "family": "tag36h11", "poseSizeMeters": 0.08255, "placement": "clusterMember",
             "localizationEligible": false, "fieldFromTagColumnMajor": NSNull()]
        ]]
    }
    private var manifest: [String: Any] {
        ["schemaVersion": 1, "finalized": true, "firstARFrameTimestamp": 1000.0,
         "fieldDefinition": ["id": packageID, "packageSha256": packageHash, "definition": definition]]
    }
    private func frame(_ id: String, _ time: Double, x: Double = 0, segment: String = "A", tracking: String = "normal") -> [String: Any] {
        var transform = identity; transform[12] = x
        return ["frameId": id, "segmentId": segment, "timestamp": 1000 + time,
                "videoPTSSeconds": time, "videoAppended": true, "tracking": tracking,
                "imageWidth": 100, "imageHeight": 100, "cameraToWorldColumnMajor": transform,
                "intrinsicsColumnMajor": calibration]
    }
    private func registration(_ time: Double = 0, segment: String = "A", x: Double = 0,
                              type: String = "fieldRegistrationChanged", alignment: String = "provisional",
                              reason: String = "Recorded single-tag anchor.") -> [String: Any] {
        var transform = identity; transform[12] = x
        return ["type": type, "timestamp": 1000 + time, "segmentId": segment,
                "packageId": packageID, "packageSha256": packageHash,
                "field": ["alignment": alignment, "anchorId": 5, "segmentId": segment,
                          "worldFromFieldColumnMajor": transform, "reason": reason]]
    }
    private func expected(_ snapshot: RecordingPlaybackSnapshot?) throws -> [RecordingPlaybackSnapshot.Polygon] {
        try XCTUnwrap(snapshot).polygons.filter { $0.style == "fieldExpected" }
    }
    private func centerX(_ snapshot: RecordingPlaybackSnapshot?) throws -> Double {
        let polygon = try XCTUnwrap(try expected(snapshot).first)
        return polygon.points.map(\.x).reduce(0,+) / Double(polygon.points.count)
    }

    func testExpectedTagsPersistBeyondObservedOutlineExpiryAndUseTheCurrentMovieCamera() throws {
        let detection: [String: Any] = ["type": "aprilTagDetections", "timestamp": 1000.0,
            "frameId": "first", "segmentId": "A", "analysisSucceeded": true,
            "detections": [["id": 5, "corners": [[20,20],[80,20],[80,80],[20,80]], "debug": ["valid": false]]]]
        let timeline = try RecordingPlaybackTimeline(manifest: manifest,
            frames: [frame("first",0),frame("moved",0.7,x:0.2),frame("last",2)],
            events: [registration(type: "fieldWalkStarted"),detection])
        let first = try XCTUnwrap(timeline.snapshot(at: 0))
        XCTAssertEqual(first.tags.count,1)
        XCTAssertEqual(try expected(first).count,1,"Moving cluster members have no permanent expected placement")
        XCTAssertEqual(try expected(first).first?.label,"Expected #5")
        XCTAssertEqual(try centerX(first),50,accuracy:1e-5)
        let moved = try XCTUnwrap(timeline.snapshot(at:0.7))
        XCTAssertTrue(moved.tags.isEmpty,"Observed outlines still expire after 0.4 seconds")
        XCTAssertEqual(try centerX(moved),40,accuracy:1e-4,"fx=100, range=2m, camera +0.2m shifts expected tag left 10px")
        XCTAssertEqual(try expected(timeline.snapshot(at:2)).count,1)
    }

    func testRegistrationChangesInvalidationAndBackwardSeekingReconstructTheirOwnState() throws {
        let invalidation: [String: Any] = ["type":"fieldRegistrationInvalidated","timestamp":1000.5,"segmentId":"A",
            "packageId":packageID,"packageSha256":packageHash,
            "field":["alignment":"unaligned","segmentId":"A","worldFromFieldColumnMajor":NSNull(),"reason":"Recorded clear"]]
        let timeline = try RecordingPlaybackTimeline(manifest:manifest,
            frames:[frame("zero",0),frame("before",0.3),frame("invalid",0.7),frame("new",1)],
            events:[registration(),invalidation,registration(0.9,x:0.4)])
        XCTAssertEqual(try centerX(timeline.snapshot(at:0.3)),50,accuracy:1e-5)
        XCTAssertTrue(try expected(timeline.snapshot(at:0.7)).isEmpty)
        XCTAssertEqual(try centerX(timeline.snapshot(at:1)),70,accuracy:1e-4)
        XCTAssertEqual(try centerX(timeline.snapshot(at:0.3)),50,accuracy:1e-5)
        XCTAssertTrue(try expected(timeline.snapshot(at:0.7)).isEmpty)
    }

    func testSegmentResetRequiresANewMatchingRegistrationAndSeekRestoresEarlierSegment() throws {
        let reset: [String:Any] = ["type":"segment","timestamp":1001.0,"segmentId":"B"]
        let timeline = try RecordingPlaybackTimeline(manifest:manifest,
            frames:[frame("A",0),frame("B",1,segment:"B"),frame("aligned-B",1.5,segment:"B")],
            events:[registration(),reset,registration(1.2,segment:"A",x:0.3),registration(1.4,segment:"B",x:0.2)])
        XCTAssertEqual(try expected(timeline.snapshot(at:0)).count,1)
        XCTAssertTrue(try expected(timeline.snapshot(at:1.3)).isEmpty,"A late old-segment result cannot register segment B")
        XCTAssertEqual(try centerX(timeline.snapshot(at:1.5)),60,accuracy:1e-4)
        XCTAssertEqual(try centerX(timeline.snapshot(at:0)),50,accuracy:1e-5)
    }

    func testLimitedVideoFramesCannotReviveFieldGeometryWithoutFreshRegistration() throws {
        let frames = [frame("start",0),frame("limited",0.5,tracking:"limited"),frame("normal",1),frame("fresh",1.5)]
        let timeline = try RecordingPlaybackTimeline(manifest:manifest,frames:frames,
            events:[registration(),registration(1.2)])
        XCTAssertTrue(try expected(timeline.snapshot(at:0.7)).isEmpty)
        XCTAssertTrue(try expected(timeline.snapshot(at:1.1)).isEmpty,"A normal frame alone must not restore old registration")
        XCTAssertEqual(try expected(timeline.snapshot(at:1.5)).count,1)
        XCTAssertEqual(try expected(timeline.snapshot(at:0)).count,1)
    }

    func testTrackingSettingsAndFloorMutationsInvalidateRegistrationEvenBetweenVideoFrames() throws {
        let boundaries: [[String:Any]] = [
            ["type":"trackingChanged","timestamp":1000.1,"segmentId":"A","tracking":"limited"],
            ["type":"settingsChanged","timestamp":1000.1,"segmentId":"A","settings":[:]],
            ["type":"floorConfirmed","timestamp":1000.1,"segmentId":"A","floor":["id":"new-floor"]],
            ["type":"floorReferenceChanged","timestamp":1000.1,"segmentId":"A","floor":NSNull()]
        ]
        for boundary in boundaries {
            let timeline = try RecordingPlaybackTimeline(manifest:manifest,
                frames:[frame("before",0),frame("after",0.3)],events:[registration(),boundary,
                ["type":"trackingChanged","timestamp":1000.2,"segmentId":"A","tracking":"normal"]])
            XCTAssertTrue(try expected(timeline.snapshot(at:0.3)).isEmpty)
            XCTAssertEqual(try expected(timeline.snapshot(at:0)).count,1)
        }
    }

    func testWarningsNeverRekeyFieldAndDegradedStateKeepsRecordedGeometry() throws {
        let warning = registration(0.2,x:100,type:"fieldAnchorWarning",alignment:"degraded",
            reason:"Tag 9 disagrees: expected height 150 cm, observed 170 cm.")
        let timeline = try RecordingPlaybackTimeline(manifest:manifest,
            frames:[frame("before",0),frame("warning",0.3),frame("degraded",0.7)],
            events:[registration(),warning,registration(0.5,alignment:"degraded",reason:"Recorded disagreement; field retained.")])
        XCTAssertEqual(try centerX(timeline.snapshot(at:0.3)),50,accuracy:1e-5)
        XCTAssertTrue(try XCTUnwrap(timeline.snapshot(at:0.3)).message?.contains("observed 170 cm") == true)
        XCTAssertEqual(try centerX(timeline.snapshot(at:0.7)),50,accuracy:1e-5)
    }

    func testWrongPackageAndMalformedRegistrationsDoNotCreatePlacements() throws {
        var otherPackage = registration();otherPackage["packageSha256"] = String(repeating:"b",count:64)
        var malformed = registration(), field = malformed["field"] as! [String:Any]
        var badMatrix = identity;badMatrix[0] = 2;field["worldFromFieldColumnMajor"] = badMatrix;malformed["field"] = field
        for event in [otherPackage,malformed,registration(alignment:"unaligned")] {
            let timeline = try RecordingPlaybackTimeline(manifest:manifest,frames:[frame("zero",0)],events:[event])
            XCTAssertTrue(try expected(timeline.snapshot(at:0)).isEmpty)
        }
        var badManifest = manifest, badDefinition = definition
        var tags = badDefinition["tags"] as! [[String:Any]];tags[0]["fieldFromTagColumnMajor"] = [1,2,3]
        badDefinition["tags"] = tags
        badManifest["fieldDefinition"] = ["id":packageID,"packageSha256":packageHash,"definition":badDefinition]
        XCTAssertThrowsError(try RecordingPlaybackTimeline(manifest:badManifest,frames:[frame("zero",0)],events:[]))
        var legacy = manifest;legacy.removeValue(forKey:"fieldDefinition")
        let old = try RecordingPlaybackTimeline(manifest:legacy,frames:[frame("zero",0)],events:[registration()])
        XCTAssertTrue(try expected(old.snapshot(at:0)).isEmpty)
        XCTAssertNil(try XCTUnwrap(old.snapshot(at:0)).message)
    }

    func testFolderLoaderVerifiesPinnedYAMLHashInventoryAndNoSymlinks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let frameData = try JSONSerialization.data(withJSONObject:frame("zero",0)), eventData = Data()
        let yaml = try JSONSerialization.data(withJSONObject:definition,options:[.sortedKeys])
        func hash(_ data:Data)->String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
        func entry(_ path:String,_ data:Data)->[String:Any] { ["path":path,"bytes":data.count,"sha256":hash(data)] }
        var saved = manifest
        saved["fieldDefinition"] = ["id":packageID,"packageSha256":hash(yaml),"definition":definition]
        saved["fileInventory"] = [entry("frames.jsonl",frameData),entry("events.jsonl",eventData),entry("field-definition.yaml",yaml)]
        let manifestURL=folder.appendingPathComponent("manifest.json"), yamlURL=folder.appendingPathComponent("field-definition.yaml")
        try JSONSerialization.data(withJSONObject:saved).write(to:manifestURL)
        try frameData.write(to:folder.appendingPathComponent("frames.jsonl"));try eventData.write(to:folder.appendingPathComponent("events.jsonl"));try yaml.write(to:yamlURL)
        XCTAssertNoThrow(try RecordingPlaybackTimeline.load(folderURL:folder))
        var tampered=yaml;tampered[0] = 91;try tampered.write(to:yamlURL)
        XCTAssertThrowsError(try RecordingPlaybackTimeline.load(folderURL:folder))
        try yaml.write(to:yamlURL)
        var descriptor=saved["fieldDefinition"] as! [String:Any];descriptor["packageSha256"]=packageHash;saved["fieldDefinition"]=descriptor
        try JSONSerialization.data(withJSONObject:saved).write(to:manifestURL)
        XCTAssertThrowsError(try RecordingPlaybackTimeline.load(folderURL:folder))
        descriptor["packageSha256"]=hash(yaml);saved["fieldDefinition"]=descriptor
        try JSONSerialization.data(withJSONObject:saved).write(to:manifestURL)
        let outside=folder.appendingPathComponent("outside.yaml");try yaml.write(to:outside)
        try FileManager.default.removeItem(at:yamlURL)
        try FileManager.default.createSymbolicLink(at:yamlURL,withDestinationURL:outside)
        XCTAssertThrowsError(try RecordingPlaybackTimeline.load(folderURL:folder))
    }
}
