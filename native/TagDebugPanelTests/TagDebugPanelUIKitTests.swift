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
        panel = TagDebugPanelView(frame: CGRect(x: 0, y: 100, width: 390, height: 270))
        controller.view.addSubview(panel)
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
    private func show(_ debug: [String: Any]?, frame: String = UUID().uuidString) {
        panel.traitCollection.performAsCurrent {
            panel.show(debug: debug, frameID: frame, timestamp: ProcessInfo.processInfo.systemUptime,
                       analysisHz: 29.7, latencyMilliseconds: 12, settings: settings)
        }
        panel.setNeedsLayout(); panel.layoutIfNeeded()
    }
    private func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }
    private func labels() -> [UILabel] { allViews(panel).compactMap { $0 as? UILabel } }
    private func label(_ text: String) throws -> UILabel {
        try XCTUnwrap(labels().first { $0.text == text }, "Missing visible value: \(text)")
    }
    private func assertReadable(file: StaticString = #filePath, line: UInt = #line) {
        for label in labels() where !(label.text ?? "").isEmpty {
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
        let rows = panel.subviews.sorted { $0.frame.minY < $1.frame.minY }
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
            UIColor.black.setFill(); context.fill(panel.bounds)
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

    func testValidMetricsAreVisibleAndFit390By270() throws {
        show(validDebug())
        for text in ["TAG #42 · VALID", "+0.123", "-0.045", "+1.234", "+12.3", "-24.5", "+36.7",
                     "1.234", "1.250", "0.016", "1.241", "28.4", "6.1"] { _ = try label(text) }
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("3×3 mean 1.251 m · HIGH · 9/9") })
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("RMS 0.42px · margin 92.1 · H0") })
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("\nAge ") && ($0.text ?? "").contains("compute 12 ms") })
        assertReadable()
        try savePNG("panel-valid-390x270")
    }

    func testAmbiguousAndMissingDepthStayReadable() throws {
        var debug = validDebug()
        debug["status"] = "ambiguous"; debug["severity"] = "warning"
        for key in ["centerDepthMeters", "depthDifferenceMeters", "meanDepthMeters", "centerConfidence"] { debug[key] = NSNull() }
        debug["validNeighborCount"] = 0
        show(debug)
        _ = try label("TAG #42 · AMBIGUOUS")
        XCTAssertGreaterThanOrEqual(labels().filter { $0.text == "—" }.count, 2)
        assertReadable()
        try savePNG("panel-ambiguous-missing-depth-390x270")
        show(nil)
        _ = try label("TAG DEBUG · WAITING")
        XCTAssertTrue(labels().contains { ($0.text ?? "").contains("29.7/30 Hz\nFrame age ") &&
            ($0.text ?? "").contains("compute 12 ms") },"No-tag footer must retain current cadence/age/compute telemetry")
        assertReadable()
        try savePNG("panel-missing-390x270")
    }

    func testDeltaColorsAreIndependentOfOverallSeverity() throws {
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
        let deltaRow = try XCTUnwrap(panel.subviews.first { row in
            row.subviews.contains { ($0 as? UILabel)?.text == "|Δ Z| · m" }
        })
        let deltaValue = try XCTUnwrap(deltaRow.subviews.compactMap { $0 as? UILabel }.last)
        XCTAssertEqual(deltaValue.text,"—")
        assertColor(deltaValue.textColor,.lightGray)
        assertReadable()
        try savePNG("panel-missing-depth-neutral-390x270")
    }

    func testDeltaThresholdBoundariesMatchMathTolerance() throws {
        for (delta,color) in [(0.10,UIColor.systemGreen),(0.10+5e-10,UIColor.systemGreen),
                              (0.15,UIColor.systemYellow),(0.15+5e-10,UIColor.systemYellow),
                              (0.15+2e-9,UIColor.systemRed)] {
            var debug=validDebug(); debug["depthDifferenceMeters"]=delta
            show(debug)
            assertColor(try label(String(format:"%.3f",delta)).textColor,color)
        }
    }

    func testRepeatedUpdatesReuseLabelsViewsAndLayers() throws {
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
}

private extension CGColor { var uiColor: UIColor { UIColor(cgColor:self) } }
