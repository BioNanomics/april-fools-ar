import XCTest
import Foundation
import UIKit
import simd

@MainActor
final class FieldDefinitionTests: XCTestCase {
    private func catalog() throws -> [FieldDefinition] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "FieldDefinitions"))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FieldDefinitionStore(catalogURL: url, importedDirectory: temporary)
        XCTAssertNil(store.error)
        return store.packages
    }
    private func field(_ tilt: Double = 0) throws -> FieldDefinition {
        let c = cos(tilt), s = sin(tilt)
        func tag(_ id: Int, _ x: Double) -> [String: Any] {
            ["id": id, "family": "tag36h11", "name": "Fixture tag \(id)",
             "poseSizeMeters": 0.1651, "placement": "fixedField", "localizationEligible": true,
             "fieldFromTagColumnMajor": [0.0,1,0,0,-s,0,-c,0,-c,0,s,0,x,3,1.5,1],
             "expectedHeightMeters": 1.5, "expectedTiltRadians": tilt]
        }
        return try FieldDefinition(["schemaVersion": 1, "id": "independent-fixture", "program": "frc", "game": "Fixture",
            "seasonStartYear": 2026, "seasonEndYear": 2026, "variant": "test", "floorElevationMeters": 0.0,
            "lengthUnit": "meter", "angleUnit": "radian", "coordinateFrame": "wpilib-blue-z-up",
            "tagFrame": "detector-x-right-y-down-z-in", "tags": [tag(1,2),tag(2,4)], "clusters": []])
    }
    private let camera = simd_double4x4(columns: (
        SIMD4(0,0,-1,0),SIMD4(0,1,0,0),SIMD4(1,0,0,0),SIMD4(8,1.7,-7,1)))
    private func metadata(_ timestamp: Double, _ frame: String, segment: String = "segment-A", floor: Bool = true, tracking: String = "normal") -> [String: Any] {
        ["frameId": frame, "segmentId": segment, "timestamp": timestamp,
         "cameraToWorldColumnMajor": FieldValue.values(camera), "tracking": tracking,
         "floorSnapshot": floor ? ["id": "field-floor", "segmentId": segment, "frameId": "floor-frame",
            "originWorldMeters": [0.0,0.2,0], "normalWorld": [0.0,1,0], "classification": "floor", "operatorConfirmed": true] as Any : NSNull()]
    }
    private func detection(_ id: Int = 1, distance: Double = 3, tilt: Double = 0, height: Double? = 1.5,
                           segment: String = "segment-A", family: String = "tag36h11", upsideDown: Bool = false) -> [String: Any] {
        let c = cos(tilt), s = sin(tilt)
        let rotation = upsideDown ? [-1.0,0,0,0,-1,0,0,0,1] : [1.0,0,0,0,c,-s,0,s,c]
        return ["id": id, "family": family, "hamming": 0, "decisionMargin": 80.0,
            "pose": ["translation": [0.0,0,distance], "rotationRowMajor": rotation,
                "rangeMeters": distance, "planeAngleDegrees": abs(tilt)*180 / .pi,
                "reprojectionRMSEPixels": 0.5, "ambiguous": false, "tagSizeMeters": 0.1651,
                "tagSizeSource": "frc-default"],
            "debug": ["status": "valid"],
            "floorHeight": ["available": height != nil, "meters": height as Any? ?? NSNull(),
                "floorId": "field-floor", "segmentId": segment, "source": "sceneDepth"],
            "gravityOrientation": ["available": true, "tiltFromVerticalDegrees": abs(tilt)*180 / .pi],
            "tagSizeResolution": ["status": "selected", "source": "frc-default", "tagSizeMeters": 0.1651]]
    }
    private func process(_ state: FieldWalkState, count: Int = 3, start: Double = 100, id: Int = 1,
                         distance: Double = 3, tilt: Double = 0, height: Double? = 1.5,
                         segment: String = "segment-A", floor: Bool = true, upsideDown: Bool = false) {
        for n in 0..<count {
            let time = start + Double(n) * 0.11
            state.process([detection(id,distance: distance,tilt: tilt,height: height,segment: segment,upsideDown: upsideDown)],
                metadata: metadata(time,"frame-\(time)",segment: segment,floor: floor), now: time+0.01, settings: TagDebugSettings())
        }
    }
    private func rows(_ state: FieldWalkState) -> [[String: Any]] { state.status["seenTags"] as? [[String: Any]] ?? [] }

    func testAllFourBundledYAMLDefinitionsValidateAndHaveExpectedSources() throws {
        let definitions = try catalog()
        XCTAssertEqual(Set(definitions.map(\.id)), ["frc-2026-rebuilt-welded","frc-2026-rebuilt-andymark","ftc-2025-2026-decode","ftc-2026-2027-biobuzz"])
        for field in definitions {
            let parsed = try FieldDefinition(FieldTextCodec.parse(field.yaml), yaml: field.yaml)
            XCTAssertEqual(parsed.hash,field.hash)
            XCTAssertTrue(NSDictionary(dictionary: parsed.raw).isEqual(to: field.raw))
            XCTAssertNotNil(field.raw["source"])
        }
        let welded = try XCTUnwrap(definitions.first { $0.variant == "welded" })
        let andymark = try XCTUnwrap(definitions.first { $0.id == "frc-2026-rebuilt-andymark" })
        XCTAssertEqual(welded.tags.count,32); XCTAssertEqual(andymark.tags.count,32)
        XCTAssertNotEqual(welded.hash,andymark.hash)
        XCTAssertNotEqual(welded.tag(1)?.fieldFromTag?[3].x,andymark.tag(1)?.fieldFromTag?[3].x)
        let decode = try XCTUnwrap(definitions.first { $0.id == "ftc-2025-2026-decode" })
        XCTAssertTrue(try XCTUnwrap(decode.tag(20)).localizationEligible)
        XCTAssertTrue(try XCTUnwrap(decode.tag(24)).localizationEligible)
        XCTAssertNil(decode.tag(21)?.fieldFromTag)
        let biobuzz = try XCTUnwrap(definitions.first { $0.id == "ftc-2026-2027-biobuzz" })
        XCTAssertEqual(biobuzz.tags.count,16)
        XCTAssertTrue(biobuzz.tags.allSatisfy { !$0.localizationEligible && $0.fieldFromTag == nil && abs($0.size - 0.08255) < 1e-10 })
    }
    func testYAMLAndJSONRoundTripsPreserveFalseNullZeroAndGeometry() throws {
        for definition in try catalog() {
            let yaml = try FieldTextCodec.yaml(definition.raw)
            let json = try FieldTextCodec.json(definition.raw)
            XCTAssertTrue(NSDictionary(dictionary: try FieldTextCodec.parse(yaml)).isEqual(to: definition.raw))
            XCTAssertTrue(NSDictionary(dictionary: try FieldTextCodec.parse(json)).isEqual(to: definition.raw))
        }
        let values: [String: Any] = ["false": false, "zero": 0, "null": NSNull(), "season": "2026–2027", "special": "a: b # not a comment"]
        let back = try FieldTextCodec.parse(FieldTextCodec.yaml(values))
        XCTAssertTrue(back["null"] is NSNull)
        XCTAssertEqual(back["false"] as? Bool,false)
        XCTAssertEqual(FieldValue.number(back["zero"]),0)
        XCTAssertEqual(back["special"] as? String,"a: b # not a comment")
    }
    func testParserRejectsDuplicateKeysAliasesTagsNonfiniteAndExcessiveNesting() {
        for text in ["a: 1\na: 2", "{\"a\":1,\"a\":2}","a: &bad 1","a: *bad","a: !unsafe value","a: .nan","a: .inf","a: 1e999","a:\n\tb: 1","a: 1\n---\nb: 2","a: [NaN]"] {
            XCTAssertThrowsError(try FieldTextCodec.parse(text),text)
        }
        let nested = String(repeating:"{\"a\":",count:34)+"0"+String(repeating:"}",count:34)
        XCTAssertThrowsError(try FieldTextCodec.parse(nested))
        XCTAssertThrowsError(try FieldTextCodec.parse("a: \""+String(repeating:"x",count:FieldTextCodec.maximumBytes)+"\""))
    }
    func testDefinitionRejectsDuplicateIDsUnknownFamiliesBadSizesAndBadTransforms() throws {
        let source = try field().raw
        var duplicate = source; duplicate["tags"] = [try XCTUnwrap((source["tags"] as? [[String:Any]])?.first),try XCTUnwrap((source["tags"] as? [[String:Any]])?.first)]
        XCTAssertThrowsError(try FieldDefinition(duplicate))
        for (key,value) in [("family","tag16h5" as Any),("poseSizeMeters",0),("localizationEligible",1),("fieldFromTagColumnMajor",Array(repeating:0.0,count:16))] {
            var invalid = source; var tags = try XCTUnwrap(source["tags"] as? [[String: Any]])
            tags[0][key] = value; invalid["tags"] = tags
            XCTAssertThrowsError(try FieldDefinition(invalid),key)
        }
    }
    func testDefinitionHashMismatchAndChangedExistingIDCannotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = FieldDefinitionStore(catalogURL: nil, importedDirectory: directory)
        let definition = try field(); let imported = try store.importDefinition(definition.yaml)
        XCTAssertEqual(imported.id,definition.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(definition.id+".yaml").path))
        XCTAssertEqual(try store.importDefinition(FieldTextCodec.json(definition.raw)).hash,imported.hash)
        var changed = definition.raw; var tags = try XCTUnwrap(changed["tags"] as? [[String: Any]])
        tags[0]["poseSizeMeters"] = 0.2; changed["tags"] = tags
        XCTAssertThrowsError(try store.importDefinition(FieldTextCodec.yaml(changed)))
        var wrongHash = definition.raw; wrongHash["packageSha256"] = "incorrect"
        XCTAssertThrowsError(try FieldDefinition(wrongHash))
        let reload = FieldDefinitionStore(catalogURL: nil, importedDirectory: directory)
        XCTAssertEqual(reload.find(definition.id)?.hash,imported.hash)
    }
    func testPresentFieldPoseMustAgreeWithItsAuthoritativeTransform() throws {
        let source = try XCTUnwrap(catalog().first { $0.id == "frc-2026-rebuilt-welded" }).raw
        let sourceTags = try XCTUnwrap(source["tags"] as? [[String: Any]])
        let sourcePose = try XCTUnwrap(sourceTags[0]["fieldPose"] as? [String: Any])
        var shifted = sourcePose
        var translation = try XCTUnwrap(sourcePose["translation"] as? [Double])
        translation[2] += 0.01; shifted["translation"] = translation
        var zeroQuaternion = sourcePose; zeroQuaternion["quaternion"] = [0.0,0,0,0]
        var wrongQuaternion = sourcePose; wrongQuaternion["quaternion"] = [1.0,0,0,0]
        var nonfinite = sourcePose; nonfinite["translation"] = [Double.nan,0,0]
        var boolean = sourcePose; boolean["quaternion"] = [true,0,0,0] as [Any]
        let invalidPoses: [Any] = [NSNull(), shifted, zeroQuaternion, wrongQuaternion, nonfinite, boolean, "not a pose"]
        for invalidPose in invalidPoses {
            var invalid = source, tags = sourceTags
            tags[0]["fieldPose"] = invalidPose; invalid["tags"] = tags
            XCTAssertThrowsError(try FieldDefinition(invalid))
        }
        var omitted = source, tags = sourceTags
        tags[0].removeValue(forKey: "fieldPose"); omitted["tags"] = tags
        XCTAssertNoThrow(try FieldDefinition(omitted)) // Older matrix-only fixtures stay readable.
        let moving = try XCTUnwrap(catalog().first { $0.id == "ftc-2026-2027-biobuzz" })
        XCTAssertNoThrow(try FieldDefinition(moving.raw)) // Null pose and null matrix remain unavailable.
    }
    func testDefinitionRejectsWrongUnitsFramesAndOutOfRangeYears() throws {
        let source=try field().raw
        for (key,value) in [("lengthUnit","inch" as Any),("angleUnit","degree"),("coordinateFrame","unknown"),("tagFrame","unknown"),("seasonEndYear",1e300),("seasonStartYear",-1)] {
            var invalid=source;invalid[key]=value
            XCTAssertThrowsError(try FieldDefinition(invalid),key)
        }
        let bio=try XCTUnwrap(catalog().first { $0.id=="ftc-2026-2027-biobuzz" })
        var invalid=bio.raw;var clusters=try XCTUnwrap(invalid["clusters"] as? [[String:Any]])
        var members=try XCTUnwrap(clusters[0]["members"] as? [[String:Any]])
        members[0]["id"]=1e300;clusters[0]["members"]=members;invalid["clusters"]=clusters
        XCTAssertThrowsError(try FieldDefinition(invalid))
    }
    func testFirstFixedTagNeedsStableThreeSourceFramesAndProducesKnownTransform() throws {
        let state = FieldWalkState(); state.select(try field()); state.beginWalk("walk")
        process(state,count:2)
        XCTAssertNil(state.worldFromField)
        process(state,count:1,start:100.22)
        let transform = try XCTUnwrap(state.worldFromField)
        let expected = [1.0,0,0,0,0,0,-1,0,0,1,0,0,3,0.2,-4,1]
        for (value,target) in zip(FieldValue.values(transform),expected) { XCTAssertEqual(value,target,accuracy:1e-8) }
        XCTAssertEqual(state.alignment,"provisional"); XCTAssertEqual(state.anchorID,1)
        XCTAssertEqual(state.status["accuracyValidated"] as? Bool,false)
        XCTAssertEqual(FieldValue.number(rows(state).first?["count"]),3)
        XCTAssertEqual(state.placements().count,2)
    }
    func testHeightMismatchWarnsWithExpectedObservedNumbersAndNeverAligns() throws {
        let state = FieldWalkState(); state.select(try field());process(state,height:1.8)
        XCTAssertNil(state.worldFromField)
        let warning = try XCTUnwrap(state.warnings.first)
        XCTAssertTrue(warning.contains("expected center height 150.0")); XCTAssertTrue(warning.contains("observed 180.0"))
        XCTAssertTrue(warning.contains("expected tilt 0.0")); XCTAssertTrue(warning.contains("Not aligned"))
        XCTAssertThrowsError(try state.requestManual())
    }
    func testMissingFloorIsUnverifiedAndManualFallbackRemainsExplicit() throws {
        let state = FieldWalkState();state.select(try field());process(state,height:nil,floor:false)
        XCTAssertNil(state.worldFromField); XCTAssertTrue(state.reason.contains("height unverified"))
        try state.requestManual(); process(state,start:100.33,height:nil,floor:false)
        XCTAssertNotNil(state.worldFromField); XCTAssertEqual(state.alignment,"provisional")
        XCTAssertTrue(state.reason.contains("Unverified manual"))
    }
    func testWrongTiltAndUpsideDownPrintedTagNeverAutoAnchor() throws {
        for (tilt,flipped) in [(20.0*Double.pi/180,false),(0.0,true)] {
            let state=FieldWalkState();state.select(try field());process(state,tilt:tilt,upsideDown:flipped)
            XCTAssertNil(state.worldFromField);XCTAssertFalse(state.warnings.isEmpty)
            XCTAssertThrowsError(try state.requestManual())
        }
    }
    func testSlopedReferenceTagPassesItsActualExpectedTilt() throws {
        let tilt=20.0*Double.pi/180,state=FieldWalkState();state.select(try field(tilt));process(state,tilt:tilt)
        XCTAssertNotNil(state.worldFromField);XCTAssertEqual(state.alignment,"provisional")
        let check=try XCTUnwrap(state.checks["tilt"] as? [String:Any])
        XCTAssertEqual(try XCTUnwrap(FieldValue.number(check["expected"])),20,accuracy:1e-8)
        XCTAssertEqual(try XCTUnwrap(FieldValue.number(check["observed"])),20,accuracy:1e-8)
    }
    func testDuplicateUIReadsAndRejectedMetricPosesKeepHonestCounts() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("walk")
        let metadata=metadata(100,"one"),good=detection()
        state.process([good],metadata:metadata,now:100.01,settings:TagDebugSettings())
        for _ in 0..<20 { _=state.status;state.process([good],metadata:metadata,now:100.01,settings:TagDebugSettings()) }
        var bad=detection();bad.removeValue(forKey:"pose");bad["debug"]=["status":"poseUnavailable"]
        state.process([bad],metadata:self.metadata(100.1,"two"),now:100.11,settings:TagDebugSettings())
        let row=try XCTUnwrap(rows(state).first)
        XCTAssertEqual(FieldValue.number(row["count"]),2);XCTAssertEqual(FieldValue.number(row["acceptedCount"]),1);XCTAssertEqual(FieldValue.number(row["rejectedCount"]),1)
        XCTAssertTrue(row["observedPosition"] is NSNull)
    }
    func testUnknownLayoutIDKeepsPoseEvidenceWithoutNominalPosition() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("walk");process(state,id:999)
        XCTAssertNil(state.worldFromField)
        let row=try XCTUnwrap(rows(state).first)
        XCTAssertEqual(row["id"] as? Int,999);XCTAssertTrue(row["nominalPosition"] is NSNull)
        XCTAssertNotNil(row["poseSizeMeters"])
    }
    func testMovingBIOBUZZMembersNeverBecomeFixedAnchors() throws {
        let bio=try XCTUnwrap(catalog().first { $0.id=="ftc-2026-2027-biobuzz" })
        let state=FieldWalkState();state.select(bio);state.beginWalk("walk")
        var d=detection(30);var pose=try XCTUnwrap(d["pose"] as? [String:Any]);pose["tagSizeMeters"]=0.08255;d["pose"]=pose
        state.process([d],metadata:metadata(100,"member30"),now:100.01,settings:TagDebugSettings())
        XCTAssertNil(state.worldFromField);XCTAssertEqual(rows(state).count,1)
        XCTAssertEqual(rows(state).first?["id"] as? Int,30)
        XCTAssertTrue(rows(state).first?["nominalPosition"] is NSNull)
        XCTAssertEqual(state.placements().count,0)
    }
    func testSegmentResetInvalidatesPlacementButPreservesSeenHistory() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("walk");process(state)
        XCTAssertNotNil(state.worldFromField)
        state.invalidate("Reset",segment:"segment-B",timestamp:101)
        XCTAssertNil(state.worldFromField);XCTAssertEqual(FieldValue.number(rows(state).first?["count"]),3)
        process(state,count:1,start:101,segment:"segment-B")
        XCTAssertNil(state.worldFromField);XCTAssertEqual(FieldValue.number(rows(state).first?["count"]),4)
        XCTAssertTrue(rows(state).first?["observedPosition"] is NSNull)
    }
    func testStopAndNewWalkBoundariesDoNotAccumulatePreviewObservations() throws {
        let state=FieldWalkState();state.select(try field());process(state)
        XCTAssertEqual(rows(state).count,0)
        state.beginWalk("one");process(state,count:1,start:101)
        XCTAssertEqual(FieldValue.number(rows(state).first?["count"]),1)
        state.stopWalk();process(state,start:102)
        XCTAssertEqual(FieldValue.number(rows(state).first?["count"]),1)
        state.beginWalk("two");XCTAssertEqual(rows(state).count,0)
    }
    func testSummaryYAMLRoundTripAndDeterministicReplayPreserveIdentity() throws {
        func capture() throws -> [String:Any] {
            let state=FieldWalkState();state.select(try field());state.beginWalk("same-walk");process(state);state.stopWalk();return state.summary
        }
        let first=try capture(),second=try capture()
        XCTAssertTrue(NSDictionary(dictionary:first).isEqual(to:second))
        let decoded=try FieldTextCodec.parse(FieldTextCodec.yaml(first))
        XCTAssertTrue(NSDictionary(dictionary:first).isEqual(to:decoded))
    }
    func testLaterDisagreeingTagWarnsWithoutRekeyingField() throws {
        let state=FieldWalkState();state.select(try field());process(state)
        let before=FieldValue.values(try XCTUnwrap(state.worldFromField))
        process(state,count:1,start:101,id:2,distance:0.5)
        XCTAssertEqual(state.alignment,"degraded")
        XCTAssertEqual(FieldValue.values(try XCTUnwrap(state.worldFromField)),before)
        XCTAssertTrue(state.warnings.contains { $0.contains("disagrees") })
    }
    func testMultipleVisiblePassingTagsDoNotOscillateFirstAnchorCandidate() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("walk")
        for n in 0..<3 {
            let time=100+Double(n)*0.11
            state.process([detection(1,distance:3),detection(2,distance:1)],metadata:metadata(time,"multi-\(n)"),now:time+0.01,settings:TagDebugSettings())
        }
        XCTAssertEqual(state.anchorID,1);XCTAssertNotNil(state.worldFromField)
        XCTAssertEqual(rows(state).count,2)
        for row in rows(state) { XCTAssertEqual(FieldValue.number(row["count"]),3) }
    }
    func testLaterYawDisagreementWarnsEvenWhenTagCenterMatches() throws {
        let state=FieldWalkState();state.select(try field());process(state)
        let before=FieldValue.values(try XCTUnwrap(state.worldFromField))
        var d=detection(2,distance:1),pose=try XCTUnwrap(detection(2,distance:1)["pose"] as? [String:Any])
        let c=cos(20*Double.pi/180),s=sin(20*Double.pi/180)
        pose["rotationRowMajor"]=[c,0,s,0,1,0,-s,0,c];d["pose"]=pose
        state.process([d],metadata:metadata(101,"yaw-mismatch"),now:101.01,settings:TagDebugSettings())
        XCTAssertEqual(state.alignment,"degraded")
        XCTAssertEqual(FieldValue.values(try XCTUnwrap(state.worldFromField)),before)
        XCTAssertTrue(state.warnings.contains { $0.contains("orientation") || $0.contains("rotation") || $0.contains("°") })
    }
    func testManualUnverifiedPermissionCannotAlignAnotherTagID() throws {
        let state=FieldWalkState();state.select(try field());process(state,height:nil,floor:false)
        try state.requestManual()
        process(state,start:100.33,id:2,distance:1,height:nil,floor:false)
        XCTAssertNil(state.worldFromField)
        state.invalidate("Reset",segment:"segment-B",timestamp:101)
        process(state,start:101,height:nil,segment:"segment-B",floor:false)
        XCTAssertNil(state.worldFromField)
    }
    func testStaleOrLimitedTrackingObservationsCannotEstablishAnchor() throws {
        let state=FieldWalkState();state.select(try field())
        state.process([detection()],metadata:metadata(100,"stale"),now:101,settings:TagDebugSettings())
        state.process([detection()],metadata:metadata(102,"limited",tracking:"limited"),now:102.01,settings:TagDebugSettings())
        XCTAssertNil(state.worldFromField)
    }
    func testTrackingLimitedAndStaleResultsRetainSeenIDsAsRejectedGeometry() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("walk")
        state.process([detection()],metadata:metadata(100,"stale"),now:101,settings:TagDebugSettings())
        state.process([detection()],metadata:metadata(102,"limited",tracking:"limited"),now:102.01,settings:TagDebugSettings())
        let row=try XCTUnwrap(rows(state).first)
        XCTAssertEqual(FieldValue.number(row["count"]),2);XCTAssertEqual(FieldValue.number(row["acceptedCount"]),0);XCTAssertEqual(FieldValue.number(row["rejectedCount"]),2)
        XCTAssertNil(state.worldFromField)
    }
    func testFamilyPlusIDIdentityDoesNotInventNominalPosition() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("walk")
        state.process([detection()],metadata:metadata(100,"known"),now:100.01,settings:TagDebugSettings())
        state.process([detection(family:"other-family")],metadata:metadata(100.1,"other"),now:100.11,settings:TagDebugSettings())
        XCTAssertEqual(rows(state).count,2)
        let other=try XCTUnwrap(rows(state).first { $0["family"] as? String=="other-family" })
        XCTAssertTrue(other["nominalPosition"] is NSNull)
        let known=try XCTUnwrap(rows(state).first { $0["family"] as? String=="tag36h11" })
        XCTAssertNotNil(known["nominalPosition"] as? [Double])
    }
    func testNewWalkDoesNotInheritOldWarnings() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("one");process(state,height:1.8)
        XCTAssertFalse(state.warnings.isEmpty)
        state.stopWalk();state.beginWalk("two")
        XCTAssertTrue(state.warnings.isEmpty);XCTAssertTrue(rows(state).isEmpty)
    }
    func testDelayedPreviousSegmentResultsCannotChangeActiveRegistration() throws {
        let state=FieldWalkState();state.select(try field());state.beginWalk("walk");process(state)
        let before=FieldValue.values(try XCTUnwrap(state.worldFromField))
        state.process([detection(segment:"old-segment")],metadata:metadata(99,"late",segment:"old-segment"),now:101,settings:TagDebugSettings(),allowRegistration:false)
        XCTAssertEqual(state.alignmentSegment,"segment-A")
        XCTAssertEqual(FieldValue.values(try XCTUnwrap(state.worldFromField)),before)
        XCTAssertEqual(FieldValue.number(rows(state).first?["count"]),4)
    }
    private func placement(_ id:Int=1, z:Float = -1, seen:Bool=false) -> FieldPlacement {
        .init(id:id,corners:[[-0.1,0.1,z],[0.1,0.1,z],[0.1,-0.1,z],[-0.1,-0.1,z]],center:[0,0,z],normal:[0,0,z+0.05],seen:seen)
    }
    private func show(_ view:FieldOverlayView,_ tags:[FieldPlacement], expired:Bool=false,degraded:Bool=false) {
        view.show(tags,degraded:degraded,cameraToWorld:matrix_identity_float4x4,
            intrinsics:simd_float3x3(columns:([100,0,0],[0,100,0],[100,100,1])),imageSize:CGSize(width:200,height:200),
            displayTransform:.identity,expiresAt:ProcessInfo.processInfo.systemUptime+(expired ? -1:1))
    }
    func testExpectedOverlayExposesReadableAccessiblePredictionsAndClearsStaleGeometry() {
        let view=FieldOverlayView(frame:CGRect(x:0,y:0,width:200,height:200))
        show(view,[placement()])
        let label=view.subviews.compactMap { $0 as? UILabel }.first { !$0.isHidden }
        XCTAssertEqual(label?.accessibilityIdentifier,"field.expected.1")
        XCTAssertTrue(label?.accessibilityValue?.contains("Not seen") == true)
        XCTAssertTrue(view.bounds.contains(label?.frame ?? .zero))
        show(view,[placement()],expired:true)
        XCTAssertTrue(view.subviews.allSatisfy(\.isHidden))
        XCTAssertTrue(view.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.allSatisfy { $0.path == nil } == true)
    }
    func testExpectedOverlayClipsBehindCameraAndReportsSeenDegradedStatus() {
        let view=FieldOverlayView(frame:CGRect(x:0,y:0,width:200,height:200))
        show(view,[placement(z:1)])
        XCTAssertFalse(view.subviews.contains { !$0.isHidden })
        show(view,[placement(seen:true)],degraded:true)
        let label=view.subviews.compactMap { $0 as? UILabel }.first { !$0.isHidden }
        XCTAssertTrue(label?.accessibilityValue?.contains("Seen in this walk") == true)
        XCTAssertTrue(label?.accessibilityValue?.contains("needs rechecking") == true)
    }
    func testExpectedOverlayBoundsLabelCountAndReusesLabels() {
        let view=FieldOverlayView(frame:CGRect(x:0,y:0,width:200,height:200))
        let tags=(1...100).map { placement($0) };show(view,tags)
        XCTAssertEqual(view.subviews.count,32)
        let original=view.subviews.map(ObjectIdentifier.init)
        for _ in 0..<100 { show(view,tags) }
        XCTAssertEqual(view.subviews.map(ObjectIdentifier.init),original)
        view.clear();XCTAssertTrue(view.subviews.allSatisfy(\.isHidden))
    }
}
