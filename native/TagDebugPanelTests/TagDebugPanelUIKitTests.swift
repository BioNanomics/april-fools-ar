import XCTest
import UIKit

/// Synthetic values are confined to this test bundle; no product demo mode.
@MainActor
final class TagDebugPanelUIKitTests: XCTestCase {
    private var window: UIWindow!
    private var panel: TagDebugPanelView!
    private let settings = TagDebugSettings()

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overrideUserInterfaceStyle = .dark
        let controller = UIViewController()
        controller.view.backgroundColor = UIColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        panel = TagDebugPanelView(frame: CGRect(x: 0, y: 100, width: 390, height: 44))
        controller.view.addSubview(panel)
        panel.onPreferredHeightChanged = { [weak self] height in self?.resizePanel(to: height) }
        panel.layoutIfNeeded()
    }
    override func tearDown() {
        window.isHidden = true
        panel = nil; window = nil
        super.tearDown()
    }

    private func validDebug() -> [String: Any] {
        ["id": 42, "status": "valid", "severity": "good",
         "translationMeters": [0.123, -0.045, 1.234], "eulerDegrees": [12.3, -24.5, 36.7],
         "rotationRowMajor": [1.0, 0, 0, 0, 1, 0, 0, 0, 1],
         "opticalPoseZMeters": 1.234, "centerDepthMeters": 1.250, "depthDifferenceMeters": 0.016,
         "rangeMeters": 1.241, "planeAngleDegrees": 28.4, "centerBearingDegrees": 6.1,
         "meanDepthMeters": 1.251, "centerConfidence": 2, "validNeighborCount": 9,
         "reprojectionRMSEPixels": 0.42, "decisionMargin": 92.1, "hamming": 0]
    }

    private func gravityLabel() throws -> UILabel {
        try XCTUnwrap(labels().first { $0.accessibilityIdentifier == "tagDebugGravityOrientation" })
    }

    func testGravityOrientationDistinguishesRawCameraAnglesAndDisplaysValidZero() throws {
        expandPanel()
        var debug = validDebug()
        debug["gravityOrientation"] = ["available": true, "reason": "valid", "tiltFromVerticalDegrees": 0.0, "twistDegrees": 0.0]
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Lean 0.0° · Upright +0.0°")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("zero degrees is a vertical tag plane") == true)
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("positive is clockwise") == true)
        XCTAssertTrue(try glossaryLink("tag-lean").accessibilityValue?.contains("zero degrees is a vertical tag plane") == true,
                      "The accessible link must retain the reading's meaning")
        XCTAssertTrue(try glossaryLink("upright-rotation").accessibilityValue?.contains("positive is clockwise") == true)
        _ = try label("Roll · °")
        _ = try label("Pitch · °")
        _ = try label("Yaw · °")
        _ = try label("+180.0")
        assertReadable()
        try savePNG("panel-gravity-orientation-390x350")
    }

    func testGravityOrientationHorizontalMissingLegacyAndTrackingUnavailableClearPreviousValues() throws {
        expandPanel()
        var debug = validDebug()
        debug["gravityOrientation"] = ["available": true, "reason": "valid", "tiltFromVerticalDegrees": 90.0, "twistDegrees": NSNull()]
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Lean 90.0° · Upright —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("horizontal tag plane") == true)
        XCTAssertTrue(try glossaryLink("upright-rotation").accessibilityValue?.contains("horizontal tag plane") == true,
                      "VoiceOver must explain why horizontal-plane twist is unavailable")
        debug["gravityOrientation"] = ["available": false, "reason": "trackingLimited", "tiltFromVerticalDegrees": 12.0, "twistDegrees": 3.0]
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Lean — · Upright —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("trackingLimited") == true)
        XCTAssertTrue(try glossaryLink("tag-lean").accessibilityValue?.contains("trackingLimited") == true)
        XCTAssertTrue(try glossaryLink("upright-rotation").accessibilityValue?.contains("trackingLimited") == true)
        debug.removeValue(forKey: "gravityOrientation")
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Lean — · Upright —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("No gravity-relative orientation in this frame") == true)
        panel.showUnavailable("Stale result")
        XCTAssertEqual(try gravityLabel().text, "Gravity · Lean — · Upright —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("Stale result") == true)
        assertReadable()
    }

    func testGravityOrientationRejectsMalformedAnglesAndFlags() throws {
        expandPanel()
        for tilt: Any in [true, Double.nan, Double.infinity, -1.0, 90.1, "12.0", NSNull()] {
            var debug = validDebug()
            debug["gravityOrientation"] = ["available": true, "tiltFromVerticalDegrees": tilt, "twistDegrees": 1.0]
            show(debug)
            XCTAssertEqual(try gravityLabel().text, "Gravity · Lean — · Upright —")
        }
        for twist: Any in [true, Double.nan, Double.infinity, -180.1, 180.1, "1.0", NSNull()] {
            var debug = validDebug()
            debug["gravityOrientation"] = ["available": true, "tiltFromVerticalDegrees": 12.5, "twistDegrees": twist]
            show(debug)
            XCTAssertEqual(try gravityLabel().text, "Gravity · Lean 12.5° · Upright —")
        }
        var debug = validDebug()
        debug["gravityOrientation"] = ["available": 1, "tiltFromVerticalDegrees": 0.0, "twistDegrees": 0.0]
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Lean — · Upright —")
        assertReadable()
    }

    func testFilteredHeightIsIdentifiedWhileDetailedPoseStaysRaw() throws {
        var filter = TagReadoutFilter()
        func row(_ meters: Double) -> [String: Any] {
            ["id": 42, "debug": validDebug(), "floorHeight": ["available": true, "meters": meters,
                "source": "sceneDepth", "floorId": "floor", "segmentId": "segment"]]
        }
        _ = filter.apply(to: [row(1)], timestamp: 10, enabled: true, samples: 5)
        let result = filter.apply(to: [row(1.6)], timestamp: 10 + 1.0 / 30, enabled: true, samples: 5)
        show(result.first?["debug"] as? [String: Any])
        XCTAssertTrue(labels().contains { $0.text?.contains("Kalman") == true })
        XCTAssertTrue(labels().contains { $0.accessibilityLabel?.contains("Detailed pose and depth metrics are raw") == true })
        expandPanel()
        XCTAssertTrue(labels().contains { $0.text?.contains("120.0 cm") == true })
        _ = try label("1.234")
        _ = try label("-0.123")
        assertReadable()
    }

    func testPassiveEmbeddedDetailsKeepTermLinksWhileBackgroundPassesThrough() throws {
        panel.configureAsPassiveReadout()
        resizePanel(to: panel.preferredHeight)
        show(validDebug())
        XCTAssertTrue(panel.isExpanded)
        let button = try detailsButton()
        XCTAssertTrue(button.isHidden)
        XCTAssertFalse(button.isAccessibilityElement)
        _ = try label("-0.123")
        _ = try label("1.234")
        let scroll = try XCTUnwrap(panel.subviews.compactMap { $0 as? UIScrollView }.first)
        XCTAssertFalse(scroll.isScrollEnabled, "The surrounding bottom sheet owns scrolling")
        let linkFrames = glossaryLinks().map { $0.convert($0.bounds, to: panel) }
        for y in stride(from: CGFloat(5), to: panel.bounds.height, by: 17) {
            for x in stride(from: CGFloat(5), to: panel.bounds.width, by: 23) {
                let point = CGPoint(x: x, y: y)
                let hit = panel.hitTest(point, with: nil)
                if linkFrames.contains(where: { $0.contains(point) }) {
                    XCTAssertTrue(hit is UIControl, "Embedded glossary terms keep native link activation")
                } else {
                    XCTAssertNil(hit, "The surrounding sheet receives background scroll gestures")
                }
            }
        }
        panel.setExpanded(false)
        XCTAssertTrue(panel.isExpanded, "An embedded readout has no independent collapsed state")
        assertReadable()
    }

    func testSeparateReadoutMountLifecycleAndFreshnessAreIndependentOfCamera() throws {
        let readout = ARCaptureReadoutView(frame: CGRect(x: 0, y: 450, width: 390, height: 350))
        var attachments = [Bool]()
        readout.onWindowAttachmentChanged = { [weak readout] view, attached in
            XCTAssertTrue(view === readout)
            attachments.append(attached)
        }
        let host = try XCTUnwrap(window.rootViewController?.view)
        host.addSubview(readout)
        readout.layoutIfNeeded()
        XCTAssertEqual(attachments, [true])
        XCTAssertEqual(readout.panel.frame, readout.bounds)
        XCTAssertEqual(readout.bounds.height, readout.panel.preferredHeight, "The embedded host must allow the added gravity row and calibration footer")
        XCTAssertNil(readout.hitTest(CGPoint(x: readout.bounds.width - 4, y: 100), with: nil))
        let profileLink = try XCTUnwrap(allViews(readout).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "tagMetricHelp-pose-profile" && !$0.isHidden
        })
        let profileFrame = profileLink.convert(profileLink.bounds, to: readout)
        XCTAssertTrue(readout.hitTest(CGPoint(x: profileFrame.midX, y: profileFrame.midY), with: nil) === profileLink,
                      "The React Native wrapper must preserve the glossary link's native hit target")
        XCTAssertTrue(readout.panel.isExpanded)
        func show(_ debug: [String: Any]?, timestamp: Double) {
            readout.panel.show(debug: preparedDebug(debug, settings: settings), frameID: UUID().uuidString, timestamp: timestamp,
                               analysisHz: 30, latencyMilliseconds: 12, settings: settings)
        }
        func contains(_ text: String) -> Bool {
            allViews(readout).compactMap { $0 as? UILabel }.contains { $0.text == text }
        }
        show(validDebug(), timestamp: ProcessInfo.processInfo.systemUptime)
        readout.layoutIfNeeded(); readout.panel.layoutIfNeeded()
        XCTAssertTrue(contains("-0.123"))
        for label in allViews(readout.panel).compactMap({ $0 as? UILabel }) where !(label.text ?? "").isEmpty && isVisible(label) {
            let bounds = label.convert(label.bounds, to: readout.panel)
            XCTAssertTrue(readout.panel.bounds.insetBy(dx: -0.5, dy: -0.5).contains(bounds),
                          "Embedded metric clipped: \(label.text ?? "")")
        }
        show(nil, timestamp: ProcessInfo.processInfo.systemUptime)
        XCTAssertFalse(contains("-0.123"))
        XCTAssertTrue(contains("TAG DEBUG · WAITING"))
        for offset in [-1.0, 1.0] {
            show(validDebug(), timestamp: ProcessInfo.processInfo.systemUptime + offset)
            XCTAssertFalse(contains("-0.123"), "Stale and future cached snapshots must stay unavailable")
        }
        show(validDebug(), timestamp: ProcessInfo.processInfo.systemUptime)
        XCTAssertTrue(contains("-0.123"))
        let expiry = expectation(description: "Embedded cached snapshot expires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { expiry.fulfill() }
        wait(for: [expiry], timeout: 1)
        XCTAssertFalse(contains("-0.123"))
        readout.removeFromSuperview()
        XCTAssertEqual(attachments, [true, false])
        host.addSubview(readout)
        XCTAssertEqual(attachments, [true, false, true])
        readout.removeFromSuperview()
    }

    private func preparedDebug(_ debug: [String: Any]?, settings configured: TagDebugSettings) -> [String: Any]? {
        guard var debug else { return nil }
        if let translation = debug["translationMeters"] as? [Double],
           let rotation = debug["rotationRowMajor"] as? [Double],
           let convention = TagPoseConvention(rawValue: configured.poseConvention),
           let readout = TagPoseReadout.evaluate(opticalPose: ["translation": translation, "rotationRowMajor": rotation], convention: convention) {
            debug["poseReadout"] = readout.dictionary
        } else {
            debug.removeValue(forKey: "poseReadout")
        }
        return debug
    }

    private func show(_ debug: [String: Any]?, frame: String = UUID().uuidString, settings configured: TagDebugSettings? = nil,
                      derivePoseReadout: Bool = true) {
        let configured = configured ?? settings
        let debug = derivePoseReadout ? preparedDebug(debug, settings: configured) : debug
        panel.traitCollection.performAsCurrent {
            panel.show(debug: debug, frameID: frame, timestamp: ProcessInfo.processInfo.systemUptime,
                       analysisHz: 29.7, latencyMilliseconds: 12, settings: configured)
        }
        panel.setNeedsLayout(); panel.layoutIfNeeded()
    }
    private func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }
    private func labels() -> [UILabel] { allViews(panel).compactMap { $0 as? UILabel } }
    private func isVisible(_ view: UIView) -> Bool {
        if view.isHidden || view.alpha <= 0 { return false }
        guard let parent=view.superview, view !== panel else { return true }
        return isVisible(parent)
    }
    private func resizePanel(to height: CGFloat) {
        panel.frame.size.height=height
        panel.setNeedsLayout(); panel.layoutIfNeeded()
    }
    private func expandPanel() {
        panel.setExpanded(true)
        resizePanel(to:panel.preferredHeight)
    }
    private func detailsButton() throws -> UIButton {
        try XCTUnwrap(allViews(panel).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "tagDebugDetailsButton"
        })
    }
    private func glossaryLinks() -> [UIButton] {
        allViews(panel).compactMap { $0 as? UIButton }.filter {
            ($0.accessibilityIdentifier ?? "").hasPrefix("tagMetricHelp-") && isVisible($0) &&
                !$0.bounds.isEmpty
        }
    }
    private func glossaryLink(_ anchor: String, named title: String? = nil) throws -> UIButton {
        try XCTUnwrap(glossaryLinks().first {
            $0.accessibilityIdentifier == "tagMetricHelp-\(anchor)" &&
                (title == nil || $0.accessibilityLabel == "Definition of " + title!)
        }, "Missing visible glossary link: \(anchor) \(title ?? "")")
    }
    private func assertWidthLinksOpenDefinition(_ titles: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        var opened = [String]()
        panel.onOpenGlossary = { opened.append($0) }
        for title in titles {
            let link = try glossaryLink("edge", named: title)
            XCTAssertTrue(link.accessibilityTraits.contains(.link), file: file, line: line)
            let frame = link.convert(link.bounds, to: panel)
            let hit = panel.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
            XCTAssertTrue(hit === link || hit?.isDescendant(of: link) == true,
                          "\(title) must receive its own visible term tap", file: file, line: line)
            link.sendActions(for: .touchUpInside)
            XCTAssertEqual(opened.last, "edge", file: file, line: line)
        }
        XCTAssertEqual(opened.count, titles.count, file: file, line: line)
    }
    private func label(_ text: String) throws -> UILabel {
        try XCTUnwrap(labels().first { $0.text == text && isVisible($0) }, "Missing visible value: \(text)")
    }
    private func metricValue(_ title: String) throws -> UILabel {
        let heading = try label(title)
        let row = try XCTUnwrap(heading.superview)
        return try XCTUnwrap(row.subviews.compactMap { $0 as? UILabel }.first {
            $0 !== heading && abs($0.frame.minX - heading.frame.minX) < 0.5 && $0.frame.minY >= heading.frame.maxY - 0.5
        }, "Missing value for \(title)")
    }
    private func assertMetric(_ title: String, equals expected: Double, accuracy: Double = 0.051,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try XCTUnwrap(try metricValue(title).text, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(Double(text), file: file, line: line), expected, accuracy: accuracy,
                       "Wrong value for \(title)", file: file, line: line)
    }

    func testCoordinateProfilesUseTheirOwnAxesRotationOrderAndSignWithoutChangingGravity() throws {
        expandPanel()
        let angle = 40.0 * Double.pi / 180
        var debug = validDebug()
        debug["translationMeters"] = [1.0, -2, 4]
        debug["rotationRowMajor"] = [cos(angle), -sin(angle), 0, sin(angle), cos(angle), 0, 0, 0, 1]
        // Deliberately incompatible legacy Euler values must not supply any profile.
        debug["eulerDegrees"] = [123.0, -87, 65]
        debug["gravityOrientation"] = ["available": true, "planeLeanFromVerticalDegrees": 12.5,
            "uprightRotationClockwiseDegrees": -3.2, "tiltFromVerticalDegrees": 88.0, "twistDegrees": 60.0]
        let cases: [(String, [String], [Double], [String], [Double])] = [
            ("rawOptical", ["X right · m", "Y down · m", "Z forward · m"], [1, -2, 4],
             ["Rot X · °", "Rot Y · °", "Rot Z · °"], [0, 0, 40]),
            ("ftcSdk", ["X right · m", "Y forward · m", "Z up · m"], [1, 4, 2],
             ["Pitch · °", "Roll · °", "Yaw · °"], [0, 40, 0]),
            ("frcPhotonVision", ["X forward · m", "Y left · m", "Z up · m"], [4, -1, 2],
             ["Roll · °", "Pitch · °", "Yaw · °"], [-40, 0, 180])
        ]
        for (convention, axes, coordinates, rotations, angles) in cases {
            var configured = settings; configured.poseConvention = convention
            show(debug, settings: configured)
            for (title, value) in zip(axes, coordinates) { try assertMetric(title, equals: value, accuracy: 0.00051) }
            for (title, value) in zip(rotations, angles) { try assertMetric(title, equals: value) }
            XCTAssertLessThan(try label(rotations[0]).frame.minX, try label(rotations[1]).frame.minX)
            XCTAssertLessThan(try label(rotations[1]).frame.minX, try label(rotations[2]).frame.minX)
            XCTAssertEqual(try gravityLabel().text, "Gravity · Lean 12.5° · Upright -3.2°")
            XCTAssertTrue(try glossaryLink("tag-lean").accessibilityValue?.contains("12.5") == true)
            XCTAssertTrue(try glossaryLink("upright-rotation").accessibilityValue?.contains("-3.2") == true)
            let profile = try XCTUnwrap(labels().first { $0.accessibilityIdentifier == "tagDebugPoseProfile" })
            XCTAssertTrue(profile.text?.contains("Tag pose relative to camera") == true)
            if convention == "rawOptical" {
                for anchor in ["optical-rotation-x", "optical-rotation-y", "optical-rotation-z"] { _ = try glossaryLink(anchor) }
            }
            assertReadable()
            try savePNG("panel-pose-\(convention)-390x350")
        }
    }

    func testFTCPitchAndYawUseSDKSignsAndAimingRangeRemainsDistinctFrom3DDistance() throws {
        expandPanel()
        var configured = settings; configured.poseConvention = "ftcSdk"
        var debug = validDebug()
        debug["translationMeters"] = [3.0, -12, 4]
        debug["cameraDistanceMeters"] = 13.0
        debug["viewingIncidenceDegrees"] = 20.0
        debug["opticalAxisOffsetDegrees"] = atan2(sqrt(153.0), 4) * 180 / Double.pi
        show(debug, settings: configured)
        try assertMetric("3D dist · m", equals: 13, accuracy: 0.00051)
        try assertMetric("XY range · m", equals: 5, accuracy: 0.00051)
        try assertMetric("Bearing · °", equals: -36.9)
        try assertMetric("Elevation · °", equals: 71.6)
        try assertMetric("Incidence · °", equals: 20)
        try assertMetric("Axis offset · °", equals: 72.1)
        for anchor in ["planar-range", "horizontal-bearing", "elevation"] {
            XCTAssertTrue(try glossaryLink(anchor).accessibilityTraits.contains(.link))
        }
        let angle = 30.0 * Double.pi / 180
        debug["rotationRowMajor"] = [cos(angle), 0, sin(angle), 0, 1, 0, -sin(angle), 0, cos(angle)]
        show(debug, settings: configured)
        try assertMetric("Yaw · °", equals: -30)
        debug["rotationRowMajor"] = [1.0, 0, 0, 0, cos(angle), -sin(angle), 0, sin(angle), cos(angle)]
        show(debug, settings: configured)
        try assertMetric("Pitch · °", equals: 30)
        assertReadable()
        try savePNG("panel-ftc-aiming-and-3d-390x350")
        show(debug)
        XCTAssertFalse(labels().contains { isVisible($0) && $0.text == "XY range · m" },
                       "FTC aiming fields must not relabel the FRC 3D diagnostics")
    }

    func testMissingMismatchedAndMalformedDerivedPoseNeverReinterpretsLegacyEulerOrInventsZero() throws {
        expandPanel()
        var legacy = validDebug()
        legacy.removeValue(forKey: "rotationRowMajor")
        show(legacy, derivePoseReadout: false)
        for title in ["X forward · m", "Y left · m", "Z up · m", "Roll · °", "Pitch · °", "Yaw · °"] {
            XCTAssertEqual(try metricValue(title).text, "—")
        }
        try assertMetric("Pose Z · m", equals: 1.234, accuracy: 0.00051)
        var mismatched = try XCTUnwrap(preparedDebug(validDebug(), settings: settings))
        var record = try XCTUnwrap(mismatched["poseReadout"] as? [String: Any])
        record["convention"] = "ftcSdk"
        mismatched["poseReadout"] = record
        show(mismatched, derivePoseReadout: false)
        XCTAssertEqual(try metricValue("Roll · °").text, "—")
        record["convention"] = "frcPhotonVision"
        record["rollPitchYawDegrees"] = [0.0, 0, 0]
        mismatched["poseReadout"] = record
        show(mismatched, derivePoseReadout: false)
        XCTAssertEqual(try metricValue("Yaw · °").text, "—", "A cached zero cannot override the authoritative rotation matrix")
        XCTAssertTrue(try glossaryLink("pose-profile").accessibilityTraits.contains(.link))
    }
    private func assertReadable(file: StaticString = #filePath, line: UInt = #line) {
        for label in labels() where isVisible(label) && !(label.text ?? "").isEmpty {
            let frame = label.convert(label.bounds, to: panel)
            XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
            XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
            XCTAssertTrue(panel.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                          "Label outside panel: \(label.text ?? "") \(frame)", file: file, line: line)
            let natural = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
            XCTAssertLessThanOrEqual(natural.height, label.bounds.height + 0.5,
                                     "Clipped text height: \(label.text ?? "")", file: file, line: line)
            if label.numberOfLines == 1 {
                let scale = label.adjustsFontSizeToFitWidth ? label.minimumScaleFactor : 1
                XCTAssertLessThanOrEqual(label.intrinsicContentSize.width * scale, label.bounds.width + 0.5,
                                         "Text cannot fit at minimum font scale: \(label.text ?? "")", file: file, line: line)
            } else if (label.text ?? "").contains("\n") {
                let lineCount = (label.text ?? "").components(separatedBy:"\n").count
                XCTAssertLessThanOrEqual(ceil(label.font.lineHeight*CGFloat(lineCount)),label.bounds.height,
                                         "Multiline footer cannot display every requested line",file:file,line:line)
            }
        }
        // Sibling metric rows must not overlap each other.
        let rows = panel.subviews.filter { isVisible($0) && !($0 is UIButton) }.sorted { $0.frame.minY < $1.frame.minY }
        for (a, b) in zip(rows, rows.dropFirst()) {
            XCTAssertLessThanOrEqual(a.frame.maxY, b.frame.minY + 0.5, "Overlapping panel rows", file: file, line: line)
        }
    }
    private func assertColor(_ actual: UIColor, _ expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        func rgba(_ color: UIColor) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: panel.traitCollection).getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r,g,b,a]
        }
        for (a,b) in zip(rgba(actual), rgba(expected)) { XCTAssertEqual(a,b,accuracy:0.001,file:file,line:line) }
    }
    private func savePNG(_ name: String) throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: panel.bounds, format: format).image { context in
            // Test-only host backdrop makes the translucent overlay visible.
            UIColor(red:0.03,green:0.08,blue:0.13,alpha:1).setFill(); context.fill(panel.bounds)
            XCTAssertTrue(panel.drawHierarchy(in: panel.bounds,afterScreenUpdates:true),
                          "UIKit failed to render the displayed panel hierarchy")
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TagDebugPanelRegression", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
        print("PANEL_PNG \(directory.appendingPathComponent(name + ".png").path)")
    }

    func testValidMetricsAreVisibleAndFit390By350() throws {
        expandPanel()
        show(validDebug())
        for text in ["TAG #42 · VALID", "-0.123", "+0.045", "+1.234", "+0.0", "+180.0",
                     "1.234", "1.250", "0.016", "1.241", "28.4", "6.1"] { _ = try label(text) }
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("3×3 mean 1.251 m · HIGH · 9/9") })
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("RMS 0.42px · margin 92.1 · H0") })
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("\nAge ") && ($0.text ?? "").contains("compute 12 ms") })
        assertReadable()
        try savePNG("panel-valid-390x350")
    }

    func testAutoSizeFooterUsesTheSelectedFTCWidthInsteadOfTheGlobalReferenceWidth() throws {
        expandPanel()
        var debug = validDebug()
        debug["tagSizeMeters"] = 0.08255
        debug["tagSizeSource"] = "sceneDepth-standard-match"
        debug["tagSizeResolution"] = ["status": "selected", "source": "sceneDepth-standard-match",
            "tagSizeMeters": 0.08255, "label": "FTC BIOBUZZ 3.25 in"]
        show(debug)
        let selectedWidth = String(format: "Edge %.1f mm", 82.55)
        let footer = try XCTUnwrap(labels().first { ($0.text ?? "").contains(selectedWidth) })
        XCTAssertTrue(footer.text?.contains("FTC") == true)
        XCTAssertTrue(footer.text?.contains("Auto") == true)
        XCTAssertFalse(labels().contains { isVisible($0) && ($0.text ?? "").contains("165.1 mm") })
        assertReadable()
        try assertWidthLinksOpenDefinition(["Edge", "Tag width source", "Field type"])
        try savePNG("panel-auto-ftc-size-390x350")
    }

    func testUnavailableAutoSizeClearsThePreviousWidthAndDirectsTheUserToSettings() throws {
        expandPanel()
        var selected = validDebug()
        selected["tagSizeMeters"] = 0.08255
        selected["tagSizeSource"] = "sceneDepth-standard-match"
        selected["tagSizeResolution"] = ["status": "selected", "source": "sceneDepth-standard-match",
            "tagSizeMeters": 0.08255, "label": "FTC BIOBUZZ 3.25 in"]
        show(selected)
        var unavailable = validDebug()
        unavailable["status"] = "sizeUnavailable"
        unavailable["severity"] = "neutral"
        unavailable["valid"] = false
        unavailable["tagSizeMeters"] = NSNull()
        unavailable["tagSizeResolution"] = ["status": "unavailable", "source": "sceneDepth-standard-match",
            "tagSizeMeters": NSNull(), "label": "Auto", "reason": "Choose a tag width in Settings."]
        for key in ["translationMeters", "eulerDegrees", "opticalPoseZMeters", "rangeMeters"] { unavailable[key] = NSNull() }
        show(unavailable)
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("Edge —") && ($0.text ?? "").contains("Auto") })
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("Settings") })
        XCTAssertFalse(labels().contains { isVisible($0) && (($0.text ?? "").contains("82.5 mm") || ($0.text ?? "").contains("82.6 mm") || ($0.text ?? "").contains("165.1 mm")) })
        assertReadable()
        try assertWidthLinksOpenDefinition(["Edge", "Tag width source", "Tag width preset", "Measured tag width", "Tag width settings"])
        try savePNG("panel-auto-size-unavailable-390x350")
    }

    func testExplicitCenterstageYearShowsPerIDWidthAndUnknownIDsCannotShowTheReferenceWidth() throws {
        expandPanel()
        let field = try settings.merging(["tagSizeMode": "ftc", "competitionYear": 2024])
        var debug = validDebug()
        debug["id"] = 7
        debug["tagSizeMeters"] = 0.127
        debug["tagSizeSource"] = "ftc-default"
        debug["tagSizeResolution"] = ["status": "selected", "fieldType": "ftc", "competitionYear": 2024,
            "source": "ftc-default", "tagSizeMeters": 0.127, "label": "FTC CENTERSTAGE 2024"]
        show(debug, settings: field)
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("Edge 127.0 mm (FTC 2024)") })
        XCTAssertFalse(labels().contains { isVisible($0) && ($0.text ?? "").contains("50.8 mm") })
        assertReadable()
        try assertWidthLinksOpenDefinition(["Edge", "Field type", "Competition year"])
        try savePNG("panel-ftc-2024-large-tag-390x350")
        debug["id"] = 42
        debug["status"] = "sizeUnavailable"
        debug["severity"] = "neutral"
        debug["tagSizeMeters"] = NSNull()
        debug["tagSizeResolution"] = ["status": "unavailable", "fieldType": "ftc", "competitionYear": 2024,
            "source": "ftc-default", "tagSizeMeters": NSNull(), "label": "FTC CENTERSTAGE 2024"]
        for key in ["translationMeters", "eulerDegrees", "opticalPoseZMeters", "rangeMeters"] { debug[key] = NSNull() }
        show(debug, settings: field)
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("Edge — (FTC 2024)") })
        XCTAssertFalse(labels().contains { isVisible($0) && (($0.text ?? "").contains("50.8 mm") || ($0.text ?? "").contains("127.0 mm")) })
        assertReadable()
        try savePNG("panel-ftc-2024-unknown-tag-390x350")
        show(nil, settings: field)
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("FTC 2024 · 29.7 Hz") })
        try assertWidthLinksOpenDefinition(["Field type", "Competition year"])
        let frc = try settings.merging(["tagSizeMode": "frc", "competitionYear": 2026])
        show(nil, settings: frc)
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("FRC 2026 · 29.7 Hz") })
        try assertWidthLinksOpenDefinition(["Field type", "Competition year"])
        show(nil)
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("Field Auto · 29.7 Hz") })
        try assertWidthLinksOpenDefinition(["Tag width source"])
    }

    func testAmbiguousAndMissingDepthStayReadable() throws {
        expandPanel()
        var debug = validDebug()
        debug["status"] = "ambiguous"; debug["severity"] = "warning"
        for key in ["centerDepthMeters", "depthDifferenceMeters", "meanDepthMeters", "centerConfidence"] { debug[key] = NSNull() }
        debug["validNeighborCount"] = 0
        show(debug)
        _ = try label("TAG #42 · AMBIGUOUS")
        XCTAssertGreaterThanOrEqual(labels().filter { $0.text == "—" }.count, 2)
        assertReadable()
        try savePNG("panel-ambiguous-missing-depth-390x350")
        show(nil)
        _ = try label("TAG DEBUG · WAITING")
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("29.7 Hz\nFrame age ") &&
            ($0.text ?? "").contains("compute 12 ms") },"No-tag footer must retain current cadence/age/compute telemetry")
        assertReadable()
        try savePNG("panel-missing-390x350")
    }

    func testDeltaColorsAreIndependentOfOverallSeverity() throws {
        expandPanel()
        for (delta, status, severity, color) in [(0.060,"badAngle","bad",UIColor.systemGreen),
                                                 (0.120,"ambiguous","warning",UIColor.systemYellow),
                                                 (0.180,"valid","good",UIColor.systemRed)] {
            var debug = validDebug()
            debug["status"] = status; debug["severity"] = severity; debug["depthDifferenceMeters"] = delta
            show(debug)
            let value = try label(String(format:"%.3f",delta))
            assertColor(value.textColor,color)
            assertColor(try XCTUnwrap(panel.layer.borderColor).uiColor,TagDebugPanelView.color(severity))
        }
        var missing = validDebug()
        missing["status"] = "missingDepth"; missing["severity"] = "neutral"
        missing["centerDepthMeters"] = NSNull(); missing["depthDifferenceMeters"] = NSNull()
        missing["meanDepthMeters"] = NSNull(); missing["centerConfidence"] = NSNull()
        missing["validNeighborCount"] = 0
        show(missing)
        _ = try label("TAG #42 · MISSING DEPTH")
        let deltaRow = try XCTUnwrap(allViews(panel).first { row in
            row.subviews.contains { ($0 as? UILabel)?.text == "|Δ Z| · m" }
        })
        let deltaValue = try XCTUnwrap(deltaRow.subviews.compactMap { $0 as? UILabel }.last)
        XCTAssertEqual(deltaValue.text,"—")
        assertColor(deltaValue.textColor,.lightGray)
        assertReadable()
        try savePNG("panel-missing-depth-neutral-390x350")
    }

    func testDeltaThresholdBoundariesMatchMathTolerance() throws {
        expandPanel()
        for (delta,color) in [(0.10,UIColor.systemGreen),(0.10+5e-10,UIColor.systemGreen),
                              (0.15,UIColor.systemYellow),(0.15+5e-10,UIColor.systemYellow),
                              (0.15+2e-9,UIColor.systemRed)] {
            var debug=validDebug(); debug["depthDifferenceMeters"]=delta
            show(debug)
            assertColor(try label(String(format:"%.3f",delta)).textColor,color)
        }
    }

    func testRepeatedUpdatesReuseLabelsViewsAndLayers() throws {
        expandPanel()
        show(validDebug()); panel.layer.displayIfNeeded()
        let viewIDs = Set(allViews(panel).map(ObjectIdentifier.init))
        let labelIDs = Set(labels().map(ObjectIdentifier.init))
        func layers(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers) }
        let layerIDs = Set(layers(panel.layer).map(ObjectIdentifier.init))
        for index in 0..<600 { show(validDebug(),frame:"reuse-\(index)") }
        XCTAssertEqual(Set(allViews(panel).map(ObjectIdentifier.init)),viewIDs)
        XCTAssertEqual(Set(labels().map(ObjectIdentifier.init)),labelIDs)
        XCTAssertEqual(Set(layers(panel.layer).map(ObjectIdentifier.init)),layerIDs)
        assertReadable()
    }

    func testCompactDefaultShowsIdentityAndTimingIn44Points() throws {
        XCTAssertFalse(panel.isExpanded)
        XCTAssertEqual(panel.preferredHeight,44)
        XCTAssertEqual(panel.bounds.height,44)
        let backdropAlpha=try XCTUnwrap(panel.backgroundColor).cgColor.alpha
        XCTAssertGreaterThan(backdropAlpha,0)
        XCTAssertLessThan(backdropAlpha,0.9,"Default panel must be visibly translucent")
        show(validDebug())
        let title=try label("TAG #42 · VALID")
        XCTAssertEqual(title.font.pointSize,12)
        XCTAssertFalse(title.font.fontDescriptor.symbolicTraits.contains(.traitBold))
        for text in ["1.234","1.250","0.016"] {
            XCTAssertFalse(labels().contains { isVisible($0) && $0.text == text },"Per-tag cards own repeated measurements; expanded Details retains raw Z values")
        }
        XCTAssertFalse(labels().contains { isVisible($0) && $0.text == "-0.123" },"Full translation row belongs in Details")
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("29.7 Hz") &&
            ($0.text ?? "").contains("age") },"Compact telemetry must include cadence and frame age")
        assertReadable()
        try savePNG("panel-compact-valid-390x44")
        show(nil)
        _=try label("TAG DEBUG · WAITING")
        XCTAssertFalse(labels().contains { isVisible($0) && $0.text == "—" },"Unavailable metric rows belong in Details")
        assertReadable()
        try savePNG("panel-compact-no-tag-390x44")
    }

    func testDetailsButtonExpandsCollapsesAndReportsPreferredHeight() throws {
        var changes=[CGFloat]()
        panel.onPreferredHeightChanged = { [weak self] height in
            changes.append(height); self?.resizePanel(to:height)
        }
        let originalSuperviewBounds=try XCTUnwrap(panel.superview).bounds
        let button=try detailsButton()
        XCTAssertEqual(button.title(for:.normal),"Details")
        button.sendActions(for:.touchUpInside)
        XCTAssertTrue(panel.isExpanded)
        XCTAssertEqual(panel.preferredHeight,350)
        XCTAssertEqual(panel.bounds.height,350)
        XCTAssertEqual(button.title(for:.normal),"Collapse")
        show(validDebug()); _=try label("-0.123")
        assertReadable()
        button.sendActions(for:.touchUpInside)
        XCTAssertFalse(panel.isExpanded)
        XCTAssertEqual(panel.preferredHeight,44)
        XCTAssertEqual(panel.bounds.height,44)
        XCTAssertEqual(button.title(for:.normal),"Details")
        XCTAssertEqual(changes,[350,44])
        XCTAssertEqual(panel.superview?.bounds,originalSuperviewBounds,"Expanding the overlay must not resize its host")
        panel.setExpanded(true); resizePanel(to:panel.preferredHeight)
        XCTAssertTrue(panel.isExpanded)
        panel.setExpanded(false); resizePanel(to:panel.preferredHeight)
        XCTAssertFalse(panel.isExpanded)
    }

    func testOnlyDisclosureAndExpandedGlossaryLinksInterceptTouches() throws {
        for expanded in [false,true] {
            panel.setExpanded(expanded); resizePanel(to:panel.preferredHeight)
            show(validDebug())
            let button=try detailsButton()
            XCTAssertGreaterThanOrEqual(button.bounds.width,44)
            XCTAssertGreaterThanOrEqual(button.bounds.height,44)
            let buttonFrame=button.convert(button.bounds,to:panel)
            XCTAssertTrue(panel.bounds.contains(buttonFrame))
            let center=CGPoint(x:buttonFrame.midX,y:buttonFrame.midY)
            let hit=try XCTUnwrap(panel.hitTest(center,with:nil))
            XCTAssertTrue(hit === button || hit.isDescendant(of:button))
            // Expanded labels own their links; remaining taps continue to tag selection.
            let linkFrames = glossaryLinks().map { $0.convert($0.bounds, to: panel) }
            if !expanded { XCTAssertTrue(linkFrames.isEmpty, "Compact telemetry must keep camera touch passthrough") }
            for y in stride(from:CGFloat(5),to:panel.bounds.height,by:17) {
                for x in stride(from:CGFloat(5),to:panel.bounds.width,by:23) {
                    let point=CGPoint(x:x,y:y)
                    if !buttonFrame.contains(point) && !linkFrames.contains(where: { $0.contains(point) }) {
                        XCTAssertNil(panel.hitTest(point,with:nil),"Panel swallowed camera tap at \(point)")
                    }
                }
            }
        }
    }

    func testEachMetricHeadingOpensItsOwnDefinitionAndExposesLinkAccessibility() throws {
        expandPanel()
        show(validDebug())
        var opened = [String]()
        panel.onOpenGlossary = { opened.append($0) }
        let anchors = ["pose-profile", "pose-x", "pose-y", "pose-z", "pose-roll", "pose-pitch", "pose-yaw",
                       "gravity", "tag-lean", "upright-rotation", "pose-depth", "scene-depth", "delta-z", "distance", "viewing-incidence", "optical-axis-offset",
                       "depth-mean", "depth-confidence", "depth-neighbors", "rms", "decision-margin", "hamming",
                       "edge", "analysis-rate", "frame-age", "compute-time"]
        for anchor in anchors {
            let link = try glossaryLink(anchor)
            XCTAssertTrue(link.accessibilityTraits.contains(.link), "\(anchor) must expose a native link role")
            XCTAssertFalse((link.accessibilityLabel ?? "").isEmpty)
            XCTAssertFalse((link.accessibilityHint ?? "").isEmpty)
            let frame = link.convert(link.bounds, to: panel)
            XCTAssertTrue(panel.bounds.contains(frame), "\(anchor) link must fit its visible label")
            let hit = panel.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
            XCTAssertTrue(hit === link || hit?.isDescendant(of: link) == true, "\(anchor) must receive its label tap")
            link.sendActions(for: .touchUpInside)
            XCTAssertEqual(opened.last, anchor)
        }
        XCTAssertEqual(opened, anchors)
        XCTAssertTrue(try glossaryLink("tag-lean").accessibilityActivate(), "VoiceOver must be able to open a term")
        XCTAssertEqual(opened.last, "tag-lean")
        XCTAssertTrue(panel.isExpanded, "Definition navigation must preserve the expanded readout")
        for text in ["-0.123", "1.234", "28.4"] {
            let value = try label(text)
            let frame = value.convert(value.bounds, to: panel)
            XCTAssertNil(panel.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil),
                         "Raw measurement values must retain camera passthrough")
        }
    }

    func testIdentityAndHeightSourceLabelsOpenMatchingDefinitions() throws {
        expandPanel()
        var debug = validDebug()
        debug["floorHeight"] = ["available": true, "meters": 1.42, "source": "sceneDepth"]
        show(debug)
        var opened = [String]()
        panel.onOpenGlossary = { opened.append($0) }
        for anchor in ["tag-id", "status", "height", "height-source", "units"] {
            try glossaryLink(anchor).sendActions(for: .touchUpInside)
            XCTAssertEqual(opened.last, anchor)
        }
    }

    func testDefinitionsRemainAvailableWithMissingMeasurementsAndNoTagTelemetry() throws {
        expandPanel()
        panel.showUnavailable("Waiting for a visible tag")
        panel.layoutIfNeeded()
        var opened = [String]()
        panel.onOpenGlossary = { opened.append($0) }
        for anchor in ["tag-lean", "upright-rotation", "pose-depth", "scene-depth", "delta-z", "viewing-incidence", "optical-axis-offset"] {
            try glossaryLink(anchor).sendActions(for: .touchUpInside)
            XCTAssertEqual(opened.last, anchor)
        }
        show(nil)
        for anchor in ["edge", "analysis-rate", "frame-age", "compute-time"] {
            try glossaryLink(anchor).sendActions(for: .touchUpInside)
            XCTAssertEqual(opened.last, anchor)
        }
        XCTAssertFalse(glossaryLinks().contains { $0.accessibilityIdentifier == "tagMetricHelp-decision-margin" },
                       "The waiting instruction must not retain stale decoder links")
    }

    func testLongStatusesRemainReadableInCompactAndExpanded() throws {
        for expanded in [false,true] {
            panel.setExpanded(expanded); resizePanel(to:panel.preferredHeight)
            for (status,title) in [("poseUnavailable","POSE UNAVAILABLE"),("trackingLimited","TRACKING LIMITED")] {
                var debug=validDebug(); debug["id"]=587; debug["status"]=status; debug["severity"]="neutral"
                show(debug)
                _=try label("TAG #587 · \(title)")
                assertReadable()
                try savePNG("panel-\(expanded ? "expanded" : "compact")-\(status)-390x\(Int(panel.bounds.height))")
            }
        }
    }

    func testRenderedDisclosureTitleSettlesToActualExpansionState() throws {
        let button=try detailsButton()
        button.sendActions(for:.touchUpInside)
        button.layoutIfNeeded()
        print("DISCLOSURE expanded immediate current=\(button.title(for:.normal) ?? "nil") rendered=\(button.titleLabel?.text ?? "nil")")
        let expandedSettled=expectation(description:"UIKit expanded disclosure update")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35) { expandedSettled.fulfill() }
        wait(for:[expandedSettled],timeout:1)
        button.layoutIfNeeded()
        print("DISCLOSURE expanded settled current=\(button.title(for:.normal) ?? "nil") rendered=\(button.titleLabel?.text ?? "nil")")
        XCTAssertTrue(panel.isExpanded)
        XCTAssertEqual(button.titleLabel?.text,"Collapse")
        show(validDebug())
        assertReadable()
        try savePNG("panel-expanded-settled-Collapse-390x350")

        button.sendActions(for:.touchUpInside)
        button.layoutIfNeeded()
        print("DISCLOSURE collapsed immediate current=\(button.title(for:.normal) ?? "nil") rendered=\(button.titleLabel?.text ?? "nil")")
        let collapsedSettled=expectation(description:"UIKit collapsed disclosure update")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.35) { collapsedSettled.fulfill() }
        wait(for:[collapsedSettled],timeout:1)
        button.layoutIfNeeded()
        print("DISCLOSURE collapsed settled current=\(button.title(for:.normal) ?? "nil") rendered=\(button.titleLabel?.text ?? "nil")")
        XCTAssertFalse(panel.isExpanded)
        XCTAssertEqual(button.titleLabel?.text,"Details")
        show(validDebug())
        assertReadable()
        try savePNG("panel-compact-settled-Details-390x44")
    }

    func testShortLandscapePanelKeepsCollapseFixedAndFooterReachableByScrolling() throws {
        expandPanel()
        panel.frame = CGRect(x: 0, y: 0, width: 440, height: 162)
        show(validDebug())
        let scroll = try XCTUnwrap(panel.subviews.compactMap { $0 as? UIScrollView }.first)
        let button = try detailsButton()
        let originalButtonFrame = button.frame
        let disclosureSettled = expectation(description: "Landscape disclosure title rendered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { disclosureSettled.fulfill() }
        wait(for: [disclosureSettled], timeout: 1)
        button.layoutIfNeeded()
        XCTAssertEqual(button.titleLabel?.text, "Collapse")
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertTrue(panel.bounds.contains(button.frame))
        let point = CGPoint(x: scroll.frame.midX, y: scroll.frame.midY)
        let hit = try XCTUnwrap(panel.hitTest(point, with: nil))
        XCTAssertTrue(hit === scroll || hit.isDescendant(of: scroll), "Constrained metrics must accept a scroll gesture")
        try savePNG("panel-expanded-landscape-440x162-top")
        scroll.contentOffset.y = scroll.contentSize.height - scroll.bounds.height
        let footer = try XCTUnwrap(labels().first { ($0.text ?? "").contains("compute 12 ms") })
        XCTAssertTrue(panel.bounds.contains(footer.convert(footer.bounds, to: panel)), "Last metrics remain reachable")
        XCTAssertEqual(button.frame, originalButtonFrame, "Collapse must not scroll away with the metrics")
        try savePNG("panel-expanded-landscape-440x162-bottom")

        resizePanel(to: panel.preferredHeight)
        XCTAssertFalse(scroll.isScrollEnabled)
        XCTAssertEqual(scroll.contentOffset, .zero, "Growing the viewport must restore all metric rows")
        XCTAssertNil(panel.hitTest(CGPoint(x: panel.bounds.width - 4, y: 100), with: nil),
                     "Unconstrained panel background returns taps to tag selection")
        scroll.contentOffset.y = -12
        panel.setNeedsLayout(); panel.layoutIfNeeded()
        XCTAssertEqual(scroll.contentOffset, .zero, "Resize cannot retain an overscrolled offset")
        assertReadable()
    }

    func testOverlayFrameBoundsTabletWidthAndLeavesShortViewportSpace() {
        for size in [CGSize(width: 390, height: 600), CGSize(width: 500, height: 250),
                     CGSize(width: 860, height: 630), CGSize(width: 480, height: 900)] {
            let viewport = CGRect(origin: .zero, size: size)
            for preferredHeight in [CGFloat(44), 350] {
                let frame = TagDebugPanelView.overlayFrame(in: viewport, preferredHeight: preferredHeight)
                XCTAssertTrue(viewport.insetBy(dx: 7.5, dy: 7.5).contains(frame))
                XCTAssertLessThanOrEqual(frame.width, 480)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
                if size.height == 250 && preferredHeight > 44 {
                    XCTAssertGreaterThanOrEqual(frame.minY, 80, "Status and camera stay visible above expanded metrics")
                }
            }
        }
    }
}

private extension CGColor { var uiColor: UIColor { UIColor(cgColor:self) } }
