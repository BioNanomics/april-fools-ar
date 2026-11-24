import XCTest
import UIKit

/// Exercises the installed Release app and its real React Native/native bridge.
/// No synthetic sensor stream is injected and no physical camera claim is made.
@MainActor
final class FieldAppUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.bionanomics.aprilfoolsar")
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let alert = springboard.alerts.firstMatch
            for title in ["Allow", "OK", "Allow While Using App"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); break }
            }
        }
    }
    private func named(_ label: String, timeout: TimeInterval = 15) -> XCUIElement {
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "Missing native accessibility element: \(label)\n\(app.debugDescription)")
        return item
    }
    private func matching(_ predicate: NSPredicate, timeout: TimeInterval = 15) -> XCUIElement {
        let item = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "Missing native element for \(predicate)\n\(app.debugDescription)")
        return item
    }
    private func tap(_ label: String) {
        let item = named(label)
        if !item.isHittable {
            for _ in 0..<4 {
                app.scrollViews.firstMatch.swipeUp()
                if item.isHittable { break }
            }
        }
        if !item.isHittable { evidence("unreachable-control-\(label)") }
        XCTAssertTrue(item.isHittable, "Native element is not reachable: \(label); enabled=\(item.isEnabled)")
        item.tap()
    }
    private func evidence(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-native-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
    func testRecordingModesAreAccessibleAndTappableInPortraitAndLandscapeWithoutRecording() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for (orientation, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation == .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed, "App did not rotate to \(name)")
            let video = named("Video + facts"), facts = named("Tag facts only")
            let record = named("Start recording")
            for mode in [video, facts] {
                XCTAssertTrue(mode.isEnabled, "Mode must be enabled before recording: \(mode.label)")
                XCTAssertTrue(mode.isHittable, "Mode must be tappable in \(name): \(mode.label)")
                XCTAssertGreaterThanOrEqual(mode.frame.width, 44)
                XCTAssertGreaterThanOrEqual(mode.frame.height, 44)
                XCTAssertTrue(app.frame.contains(mode.frame), "Mode lies outside the visible app: \(mode.frame)")
                XCTAssertFalse(mode.frame.intersects(record.frame), "Mode overlaps the Record button in \(name)")
            }
            XCTAssertTrue(video.isSelected, "Video + facts should start selected in \(name)")
            XCTAssertFalse(facts.isSelected)
            evidence("field-recording-modes-\(name)-video-native")
            facts.tap()
            let factsSelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: facts)
            XCTAssertEqual(XCTWaiter.wait(for: [factsSelected], timeout: 5), .completed)
            XCTAssertFalse(video.isSelected)
            XCTAssertTrue(record.exists, "Changing the mode must leave recording stopped")
            XCTAssertFalse(app.buttons["Stop and save recording"].exists)
            evidence("field-recording-modes-\(name)-facts-native")
            video.tap()
            let videoSelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: video)
            XCTAssertEqual(XCTWaiter.wait(for: [videoSelected], timeout: 5), .completed)
            XCTAssertFalse(facts.isSelected)
            XCTAssertTrue(record.exists, "Switching back must leave recording stopped")
        }
    }
    func testBundledCatalogSelectionAndYAMLUseRealNativeBridge() {
        tap("Field definitions and tags seen")
        _ = named("Choose field")
        let selector = NSPredicate(format: "label BEGINSWITH %@", "Select ")
        _ = matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Select ", "BIOBUZZ"))
        let labels = Set(app.descendants(matching: .any).matching(selector).allElementsBoundByIndex.map(\.label))
        XCTAssertEqual(labels.count,4, "Actual bundled catalog should expose exactly four package choices: \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("REBUILT") && $0.contains("welded") })
        XCTAssertTrue(labels.contains { $0.contains("REBUILT") && $0.contains("andymark") })
        XCTAssertTrue(labels.contains { $0.contains("DECODE") })
        evidence("field-catalog-native")
        let welded = matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@", "Select ", "REBUILT", "welded"))
        welded.tap()
        tap("Use selected field")
        _ = matching(NSPredicate(format: "label CONTAINS %@", "Tags seen: 0 / 32 expected"))
        _ = named("Recheck field alignment")
        evidence("field-walk-native")
        tap("View YAML")
        _ = named("Field definition YAML")
        let document = named("Field YAML document")
        let value = document.value as? String
        XCTAssertNotNil(value,"The visible YAML must be available through native accessibility.")
        XCTAssertTrue(value?.contains("frc-2026-rebuilt-welded") == true,"The native YAML response must describe the selected package.")
        XCTAssertTrue(value?.contains("poseSizeMeters") == true)
        evidence("field-yaml-native")
        tap("Close field definitions")
        _ = named("Field definitions and tags seen")
        tap("Field definitions and tags seen")
        _ = matching(NSPredicate(format: "label CONTAINS %@", "Tags seen: 0 / 32 expected"))
    }
    func testJSONImportIsValidatedByNativeBridgeAndDisplaysYAML() throws {
        tap("Field definitions and tags seen")
        tap("Import YAML or JSON")
        // iOS appends the TextView placeholder to its accessible label.
        let input = matching(NSPredicate(format: "label BEGINSWITH %@", "Field definition YAML or JSON"))
        input.tap()
        let sample: [String: Any] = ["schemaVersion":1,"id":"ui-import-fixture","program":"frc","game":"UI Bridge Fixture",
            "seasonStartYear":2026,"seasonEndYear":2026,"variant":"test","floorElevationMeters":0,
            "lengthUnit":"meter","angleUnit":"radian","coordinateFrame":"wpilib-blue-z-up","tagFrame":"detector-x-right-y-down-z-in",
            "tags":[["id":99,"family":"tag36h11","name":"Unregistered print","poseSizeMeters":0.1651,
                "placement":"unknown","localizationEligible":false,"fieldFromTagColumnMajor":NSNull(),"fieldPose":NSNull()]],"clusters":[]]
        let json = String(decoding:try JSONSerialization.data(withJSONObject:sample,options:[.sortedKeys,.withoutEscapingSlashes]),as:UTF8.self)
        input.typeText(json)
        tap("Hide keyboard")
        tap("Validate and use imported field")
        _ = matching(NSPredicate(format:"label CONTAINS %@","UI Bridge Fixture"))
        _ = matching(NSPredicate(format:"label CONTAINS %@","Tags seen: 0 / 1 expected"))
        evidence("field-imported-native")
        tap("View YAML")
        _ = named("Field definition YAML")
        let document = named("Field YAML document")
        let value = try XCTUnwrap(document.value as? String,"Imported YAML must expose its contents through native accessibility")
        XCTAssertTrue(value.contains("ui-import-fixture"))
        XCTAssertFalse(value.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("{"),"Imported JSON must display normalized YAML")
        evidence("field-imported-yaml-native")
    }
}
