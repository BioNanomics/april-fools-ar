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
        XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt 0.0° · Twist +0.0°")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("zero degrees is a vertical tag plane") == true)
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("positive is clockwise") == true)
        _ = try label("Cam roll · °")
        _ = try label("Cam pitch · °")
        _ = try label("Cam yaw · °")
        _ = try label("+12.3")
        assertReadable()
        try savePNG("panel-gravity-orientation-390x290")
    }

    func testGravityOrientationHorizontalMissingLegacyAndTrackingUnavailableClearPreviousValues() throws {
        expandPanel()
        var debug = validDebug()
        debug["gravityOrientation"] = ["available": true, "reason": "valid", "tiltFromVerticalDegrees": 90.0, "twistDegrees": NSNull()]
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt 90.0° · Twist —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("horizontal tag plane") == true)
        debug["gravityOrientation"] = ["available": false, "reason": "trackingLimited", "tiltFromVerticalDegrees": 12.0, "twistDegrees": 3.0]
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt — · Twist —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("trackingLimited") == true)
        debug.removeValue(forKey: "gravityOrientation")
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt — · Twist —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("No gravity-relative orientation in this frame") == true)
        panel.showUnavailable("Stale result")
        XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt — · Twist —")
        XCTAssertTrue(try gravityLabel().accessibilityValue?.contains("Stale result") == true)
        assertReadable()
    }

    func testGravityOrientationRejectsMalformedAnglesAndFlags() throws {
        expandPanel()
        for tilt: Any in [true, Double.nan, Double.infinity, -1.0, 90.1, "12.0", NSNull()] {
            var debug = validDebug()
            debug["gravityOrientation"] = ["available": true, "tiltFromVerticalDegrees": tilt, "twistDegrees": 1.0]
            show(debug)
            XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt — · Twist —")
        }
        for twist: Any in [true, Double.nan, Double.infinity, -180.1, 180.1, "1.0", NSNull()] {
            var debug = validDebug()
            debug["gravityOrientation"] = ["available": true, "tiltFromVerticalDegrees": 12.5, "twistDegrees": twist]
            show(debug)
            XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt 12.5° · Twist —")
        }
        var debug = validDebug()
        debug["gravityOrientation"] = ["available": 1, "tiltFromVerticalDegrees": 0.0, "twistDegrees": 0.0]
        show(debug)
        XCTAssertEqual(try gravityLabel().text, "Gravity · Tilt — · Twist —")
        assertReadable()
    }

    private func show(_ debug: [String: Any]?, frame: String = UUID().uuidString, settings configured: TagDebugSettings? = nil) {
        panel.traitCollection.performAsCurrent {
            panel.show(debug: debug, frameID: frame, timestamp: ProcessInfo.processInfo.systemUptime,
                       analysisHz: 29.7, latencyMilliseconds: 12, settings: configured ?? settings)
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
    private func label(_ text: String) throws -> UILabel {
        try XCTUnwrap(labels().first { $0.text == text && isVisible($0) }, "Missing visible value: \(text)")
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

    func testValidMetricsAreVisibleAndFit390By290() throws {
        expandPanel()
        show(validDebug())
        for text in ["TAG #42 · VALID", "+0.123", "-0.045", "+1.234", "+12.3", "-24.5", "+36.7",
                     "1.234", "1.250", "0.016", "1.241", "28.4", "6.1"] { _ = try label(text) }
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("3×3 mean 1.251 m · HIGH · 9/9") })
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("RMS 0.42px · margin 92.1 · H0") })
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("\nAge ") && ($0.text ?? "").contains("compute 12 ms") })
        assertReadable()
        try savePNG("panel-valid-390x290")
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
        try savePNG("panel-auto-ftc-size-390x290")
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
        try savePNG("panel-auto-size-unavailable-390x290")
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
        try savePNG("panel-ftc-2024-large-tag-390x290")
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
        try savePNG("panel-ftc-2024-unknown-tag-390x290")
        show(nil, settings: field)
        XCTAssertTrue(labels().contains { isVisible($0) && ($0.text ?? "").contains("FTC 2024 · 29.7 Hz") })
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
        try savePNG("panel-ambiguous-missing-depth-390x290")
        show(nil)
        _ = try label("TAG DEBUG · WAITING")
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("29.7 Hz\nFrame age ") &&
            ($0.text ?? "").contains("compute 12 ms") },"No-tag footer must retain current cadence/age/compute telemetry")
        assertReadable()
        try savePNG("panel-missing-390x290")
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
        try savePNG("panel-missing-depth-neutral-390x290")
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
        XCTAssertFalse(labels().contains { isVisible($0) && $0.text == "+0.123" },"Full translation row belongs in Details")
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
        XCTAssertEqual(panel.preferredHeight,290)
        XCTAssertEqual(panel.bounds.height,290)
        XCTAssertEqual(button.title(for:.normal),"Collapse")
        show(validDebug()); _=try label("+0.123")
        assertReadable()
        button.sendActions(for:.touchUpInside)
        XCTAssertFalse(panel.isExpanded)
        XCTAssertEqual(panel.preferredHeight,44)
        XCTAssertEqual(panel.bounds.height,44)
        XCTAssertEqual(button.title(for:.normal),"Details")
        XCTAssertEqual(changes,[290,44])
        XCTAssertEqual(panel.superview?.bounds,originalSuperviewBounds,"Expanding the overlay must not resize its host")
        panel.setExpanded(true); resizePanel(to:panel.preferredHeight)
        XCTAssertTrue(panel.isExpanded)
        panel.setExpanded(false); resizePanel(to:panel.preferredHeight)
        XCTAssertFalse(panel.isExpanded)
    }

    func testOnly44PointDetailsButtonInterceptsTouches() throws {
        for expanded in [false,true] {
            panel.setExpanded(expanded); resizePanel(to:panel.preferredHeight)
            let button=try detailsButton()
            XCTAssertGreaterThanOrEqual(button.bounds.width,44)
            XCTAssertGreaterThanOrEqual(button.bounds.height,44)
            let buttonFrame=button.convert(button.bounds,to:panel)
            XCTAssertTrue(panel.bounds.contains(buttonFrame))
            let center=CGPoint(x:buttonFrame.midX,y:buttonFrame.midY)
            let hit=try XCTUnwrap(panel.hitTest(center,with:nil))
            XCTAssertTrue(hit === button || hit.isDescendant(of:button))
            // All metric/title/background taps must continue to the camera view.
            for y in stride(from:CGFloat(5),to:panel.bounds.height,by:17) {
                for x in stride(from:CGFloat(5),to:panel.bounds.width,by:23) {
                    let point=CGPoint(x:x,y:y)
                    if !buttonFrame.contains(point) {
                        XCTAssertNil(panel.hitTest(point,with:nil),"Panel swallowed camera tap at \(point)")
                    }
                }
            }
        }
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
        try savePNG("panel-expanded-settled-Collapse-390x290")

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
        XCTAssertNil(panel.hitTest(CGPoint(x: 20, y: 100), with: nil), "Unconstrained readout returns taps to tag selection")
        scroll.contentOffset.y = -12
        panel.setNeedsLayout(); panel.layoutIfNeeded()
        XCTAssertEqual(scroll.contentOffset, .zero, "Resize cannot retain an overscrolled offset")
        assertReadable()
    }

    func testOverlayFrameBoundsTabletWidthAndLeavesShortViewportSpace() {
        for size in [CGSize(width: 390, height: 600), CGSize(width: 500, height: 250),
                     CGSize(width: 860, height: 630), CGSize(width: 480, height: 900)] {
            let viewport = CGRect(origin: .zero, size: size)
            for preferredHeight in [CGFloat(44), 290] {
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
