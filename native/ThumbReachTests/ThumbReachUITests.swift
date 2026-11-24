import XCTest
import UIKit

/// Tests the actual bundled React Native app through its native accessibility tree.
final class ThumbReachUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.bionanomics.aprilfoolsar")
    private let versionButtonLabel = "Open version and release notes"
    private var recordedNavigationTrees = Set<String>()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(control("More controls").waitForExistence(timeout: 20), app.debugDescription)
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func control(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
    }

    private func navigationControl(_ label: String, in navigation: String) -> XCUIElement {
        // Fabric may expose the navigation testID as a leaf beside its accessible tabs.
        // Scope by its native frame rather than requiring an accessibility parent/child link.
        let bounds = control(navigation).frame.insetBy(dx: -1, dy: -1)
        let matches = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR identifier == %@", label, label))
        if recordedNavigationTrees.insert(navigation).inserted {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = navigation + "-native-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            print("THUMB_NAV \(navigation) frame=\(bounds) descendants=\(control(navigation).descendants(matching: .any).count) globalMatches=\(matches.count)")
        }
        return matches.allElementsBoundByIndex.first {
            $0.exists && bounds.contains($0.frame) && $0.isHittable
        } ?? matches.firstMatch
    }

    private func tapNavigation(_ label: String, in navigation: String) {
        let element = navigationControl(label, in: navigation)
        XCTAssertTrue(element.exists && element.isHittable, "Unreachable navigation: \(label)")
        element.tap()
    }

    private func tap(_ label: String, scroll: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let element = control(label)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(label). \(app.debugDescription)", file: file, line: line)
        if scroll {
            for _ in 0..<5 where !element.isHittable {
                app.scrollViews.firstMatch.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "Unreachable \(label): \(element.frame). \(app.debugDescription)", file: file, line: line)
        element.tap()
    }

    private func assertCaptureControlsPosition(_ state: String, file: StaticString = #filePath, line: UInt = #line) {
        assertVersionBadge(state, file: file, line: line)
        let screen = app.frame
        XCTAssertGreaterThan(screen.height, 0, file: file, line: line)
        let landscape = screen.width > screen.height
        let types: Set<XCUIElement.ElementType> = [.button, .checkBox, .tab, .switch, .textField, .textView, .slider]
        var inspected = [String]()
        let explicitlyNamed = ["Tag debug mode", "Measurement mode", "Saved sessions", "Kalman filter", "Tag details",
                               "Privacy", "Licenses & notices", "Sponsors"].map(control)
        let typeValues = types.map { NSNumber(value: $0.rawValue) }
        let typed = app.descendants(matching: .any).matching(
            NSPredicate(format: "elementType IN %@", typeValues)).allElementsBoundByIndex
        for element in explicitlyNamed + typed {
            guard element.exists else { continue }
            let frame = element.frame
            guard !frame.isEmpty, frame.intersects(screen), element.isHittable else { continue }
            // The user explicitly permits this single upper-right navigation control.
            if element.label == versionButtonLabel { continue }
            inspected.append("\(element.elementType.rawValue):\(element.label):\(frame)")
            if landscape {
                XCTAssertGreaterThanOrEqual(frame.minX, screen.midX - 1,
                    "\(state): \(element.label) must stay on the right in landscape: \(frame); screen \(screen)", file: file, line: line)
            } else {
                XCTAssertGreaterThanOrEqual(frame.minY, screen.midY - 1,
                    "\(state): \(element.label) is above the portrait thumb area: \(frame); screen \(screen)", file: file, line: line)
            }
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + 1, file: file, line: line)
        }
        XCTAssertFalse(inspected.isEmpty, "No interactive native elements inspected for \(state)", file: file, line: line)
        if landscape {
            let sheet = control("debug.settings.sheet")
            let rail = sheet.exists ? sheet : control("capture.thumbDock")
            XCTAssertTrue(rail.exists, "Missing landscape side panel in \(state)", file: file, line: line)
            let frame = rail.frame
            XCTAssertGreaterThanOrEqual(frame.minX, screen.midX - 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, control(versionButtonLabel).frame.maxY - 1,
                "Landscape controls must clear the persistent version button", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 1, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + 1, file: file, line: line)
            XCTAssertGreaterThan(frame.height, screen.height / 2,
                "Landscape uses a tall side panel rather than a lower-half sheet", file: file, line: line)
            print("THUMB_SIDE \(state) screen=\(screen) panel=\(frame)")
        }
        print("THUMB_FRAMES \(state) screen=\(screen) \(inspected.joined(separator: " | "))")
    }

    private func assertPrimaryControls(_ state: String, file: StaticString = #filePath, line: UInt = #line) {
        for label in ["Tag debug mode", "Measurement mode", "Saved sessions", "Tag details", "More controls",
                      "Kalman filter", "View zoom 1×", "View zoom 2×", "View zoom 4×", "Debug settings",
                      "Edit session name", "Start recording"] {
            let element = control(label)
            XCTAssertTrue(element.exists && element.isHittable, "Unreachable primary control in \(state): \(label)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(element.frame.width, 44, "Narrow touch target: \(label)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(element.frame.height, 44, "Short touch target: \(label)", file: file, line: line)
        }
    }

    private func assertVersionBadge(_ state: String, file: StaticString = #filePath, line: UInt = #line) {
        let badge = control(versionButtonLabel)
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "Missing version badge in \(state)", file: file, line: line)
        let environment = ProcessInfo.processInfo.environment
        guard let version = environment["THUMB_EXPECTED_VERSION"], let build = environment["THUMB_EXPECTED_BUILD"] else {
            XCTFail("Harness must supply the installed app version and build", file: file, line: line)
            return
        }
        let expected = "Version \(version), build \(build)"
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: badge)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed,
                       "Wrong version badge in \(state): \(badge.debugDescription)", file: file, line: line)
        XCTAssertEqual(badge.elementType, .button, "Version badge must expose its navigation action", file: file, line: line)
        let screen = app.frame, frame = badge.frame
        XCTAssertFalse(frame.isEmpty, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, screen.midX, "Version badge belongs on the right", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY, file: file, line: line)
        XCTAssertLessThan(frame.maxY, screen.midY, "Version badge belongs above the thumb controls", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 44, file: file, line: line)
        print("THUMB_VERSION \(state) value=\(badge.value ?? "nil") frame=\(frame) screen=\(screen)")
    }

    private func assertFullScreenInfo(_ state: String, prefix: String, navigation: String, labels: [String],
                                      file: StaticString = #filePath, line: UInt = #line) {
        let root = control(prefix + ".screen")
        XCTAssertTrue(root.waitForExistence(timeout: 10), "Missing full-screen \(state)", file: file, line: line)
        assertVersionBadge(state, file: file, line: line)
        let screen = app.frame, frame = root.frame
        XCTAssertEqual(frame.minX, screen.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.minY, screen.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.maxX, screen.maxX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 1, file: file, line: line)
        let content = control(prefix + ".content").frame
        // A safe-area/header allowance keeps this focused on full-page reading space.
        XCTAssertLessThanOrEqual(content.minY, screen.minY + screen.height / 4 + 8, file: file, line: line)
        XCTAssertGreaterThan(content.height, screen.height / 2, "Full-screen content must exceed a half sheet", file: file, line: line)
        let nav = control(navigation).frame
        XCTAssertGreaterThanOrEqual(nav.minY, screen.midY - 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(nav.height, 44, file: file, line: line)
        for label in labels {
            let element = navigationControl(label, in: navigation)
            XCTAssertTrue(element.exists && element.isHittable, "Unreachable bottom navigation: \(label)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(element.frame.minY, screen.midY - 1, file: file, line: line)
            XCTAssertTrue(nav.insetBy(dx: -1, dy: -1).contains(element.frame), "\(label) must stay in its fixed bottom navigation", file: file, line: line)
        }
        print("THUMB_INFO \(state) screen=\(screen) root=\(frame) content=\(content) navigation=\(nav)")
    }

    private func assertVersionPage(_ state: String) {
        assertFullScreenInfo(state, prefix: "release.notes", navigation: "release.notes.navigation",
                             labels: ["Version", "Release notes", "Close release notes"])
        XCTAssertTrue(navigationControl("Version", in: "release.notes.navigation").isSelected)
        XCTAssertTrue(control("installed-build-details").exists)
    }

    private func exerciseVersionTabs(_ name: String) throws {
        assertVersionPage("\(name)-version")
        try saveScreenshot("\(name)-version")
        tapNavigation("Release notes", in: "release.notes.navigation")
        assertFullScreenInfo("\(name)-release-notes", prefix: "release.notes", navigation: "release.notes.navigation",
                             labels: ["Version", "Release notes", "Close release notes"])
        XCTAssertTrue(navigationControl("Release notes", in: "release.notes.navigation").isSelected)
        XCTAssertTrue(control("current-release").exists)
        try saveScreenshot("\(name)-release-notes")
        // The badge on this page changes tabs locally without stacking another native Modal.
        tap(versionButtonLabel)
        assertVersionPage("\(name)-badge-return-to-version")
        tap("Close release notes")
    }

    private func saveScreenshot(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThumbReach", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(name + ".png")
        try screenshot.pngRepresentation.write(to: output)
        print("THUMB_PNG \(output.path)")
        print("THUMB_SCREEN \(name) pixels=\(screenshot.image.cgImage?.width ?? 0)x\(screenshot.image.cgImage?.height ?? 0) orientation=\(screenshot.image.imageOrientation.rawValue) appFrame=\(app.frame)")
    }

    private func exercise(_ orientation: UIDeviceOrientation, name: String) throws {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            landscape ? self.app.frame.width > self.app.frame.height : self.app.frame.height > self.app.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        XCTAssertTrue(control("More controls").waitForExistence(timeout: 5))
        let settled = expectation(description: "Native rotation finishes rendering")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        assertCaptureControlsPosition("\(name)-capture")
        assertPrimaryControls("\(name)-capture")
        try saveScreenshot("\(name)-capture")

        tap(versionButtonLabel)
        try exerciseVersionTabs("\(name)-badge")
        XCTAssertTrue(control("More controls").waitForExistence(timeout: 5))

        tap("Kalman filter")
        XCTAssertTrue(control("Kalman filter").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-filtered")
        tap("View zoom 2×")
        assertCaptureControlsPosition("\(name)-zoom")

        tap("Edit session name")
        XCTAssertTrue(control("Session name").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-name")
        tap("Close capture tools")

        tap("Debug settings")
        XCTAssertTrue(control("Apply debug settings").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-settings")
        try saveScreenshot("\(name)-settings")
        tap(versionButtonLabel)
        assertVersionPage("\(name)-settings-to-version")
        XCTAssertFalse(control("Apply debug settings").exists, "Settings must finish dismissal before Version opens")
        tap("Close release notes")

        tap("Measurement mode")
        XCTAssertTrue(control("Close capture tools").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-measure")
        try saveScreenshot("\(name)-measure")
        tap("Close capture tools")
        tap("Tag debug mode")

        tap("More controls")
        XCTAssertTrue(control("Close capture tools").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-more")
        tap("Version and release notes", scroll: true)
        assertVersionPage("\(name)-more-to-version")
        tap("Close release notes")
        tap("More controls")
        tap("About and sponsors", scroll: true)
        assertFullScreenInfo("\(name)-about", prefix: "about", navigation: "about.bottomNav",
                             labels: ["About", "Privacy", "Licenses & notices", "Close about and privacy"])
        XCTAssertTrue(navigationControl("About", in: "about.bottomNav").isSelected)
        XCTAssertTrue(control("about-and-sponsors").exists)
        XCTAssertTrue(control("Don Wood Foundation website").exists)
        XCTAssertTrue(control("Medical Informatics Engineering website").exists)
        try saveScreenshot("\(name)-about")
        tapNavigation("Privacy", in: "about.bottomNav")
        assertFullScreenInfo("\(name)-privacy", prefix: "about", navigation: "about.bottomNav",
                             labels: ["About", "Privacy", "Licenses & notices", "Close about and privacy"])
        XCTAssertTrue(navigationControl("Privacy", in: "about.bottomNav").isSelected)
        XCTAssertTrue(control("privacy-policy").exists)
        tapNavigation("Licenses & notices", in: "about.bottomNav")
        assertFullScreenInfo("\(name)-licenses", prefix: "about", navigation: "about.bottomNav",
                             labels: ["About", "Privacy", "Licenses & notices", "Close about and privacy"])
        XCTAssertTrue(navigationControl("Licenses & notices", in: "about.bottomNav").isSelected)
        XCTAssertTrue(control("app-license").exists)
        tapNavigation("About", in: "about.bottomNav")
        XCTAssertTrue(navigationControl("About", in: "about.bottomNav").isSelected)
        XCTAssertTrue(control("about-and-sponsors").exists)
        tap(versionButtonLabel)
        assertVersionPage("\(name)-about-to-version")
        XCTAssertFalse(control("about.screen").exists, "About must finish dismissal before Version opens")
        tap("Close release notes")
        tap("Tag details")
        XCTAssertTrue(control("capture.tagReadout").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-details")
        try saveScreenshot("\(name)-details")
        tap("Close capture tools")

        tap("Saved sessions")
        XCTAssertTrue(control("Refresh saved sessions").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-saved")
        try saveScreenshot("\(name)-saved")
        tap(versionButtonLabel)
        assertVersionPage("\(name)-saved-to-version")
        tap("Close release notes")
        XCTAssertTrue(control("Refresh saved sessions").waitForExistence(timeout: 5), "Done must return to Saved")
        tap("Tag details")
        XCTAssertTrue(control("capture.tagReadout").waitForExistence(timeout: 5))
        assertCaptureControlsPosition("\(name)-saved-to-details")
        tap("Close capture tools")
        tap("Tag debug mode")
        assertCaptureControlsPosition("\(name)-returned")
        assertPrimaryControls("\(name)-returned")
        XCTAssertTrue(control("View zoom 2×").isSelected, "Zoom selection must survive the information and tools flows")
        if landscape {
            XCUIDevice.shared.orientation = .portrait
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.app.frame.height > self.app.frame.width
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
            let position = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.control("Start recording").frame.minY >= self.app.frame.midY - 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [position], timeout: 5), .completed)
            assertCaptureControlsPosition("\(name)-portrait-return")
            assertPrimaryControls("\(name)-portrait-return")
            XCTAssertTrue(control("View zoom 2×").isSelected, "Rotation must preserve zoom selection")
            try saveScreenshot("\(name)-portrait-return")
        }
    }

    func testPortraitControlsStayWithinThumbArea() throws {
        try exercise(.portrait, name: "portrait")
    }

    func testLandscapeLeftControlsStayOnRightSide() throws {
        try exercise(.landscapeLeft, name: "landscape-left")
    }

    func testLandscapeRightControlsStayOnRightSide() throws {
        try exercise(.landscapeRight, name: "landscape-right")
    }
}
