import XCTest
import UIKit
import WebKit

/// Exercises the same offline resource and native sheet used by label links.
@MainActor
final class TagMetricGlossaryUIKitTests: XCTestCase {
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func evaluate(_ script: String, in webView: WKWebView) throws -> Any? {
        let complete = expectation(description: "Inspect rendered glossary")
        var result: Any?
        var failure: Error?
        webView.evaluateJavaScript(script) { value, error in
            result = value
            failure = error
            complete.fulfill()
        }
        wait(for: [complete], timeout: 10)
        if let failure { throw failure }
        return result
    }

    private func savePNG(_ name: String, webView: WKWebView) throws {
        let taken = expectation(description: "Snapshot rendered glossary")
        var result: UIImage?
        var failure: Error?
        webView.takeSnapshot(with: nil) { image, error in
            result = image
            failure = error
            taken.fulfill()
        }
        wait(for: [taken], timeout: 10)
        if let failure { throw failure }
        let image = try XCTUnwrap(result)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TagDebugPanelRegression", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("GLOSSARY_PNG \(path.path)")
    }

    func testBundledDocumentDefinesEveryLinkedTermAndContainsLocalDiagrams() throws {
        let anchors = ["x-right", "y-down", "z-forward", "camera-roll", "camera-pitch", "camera-yaw",
                       "gravity", "tilt", "twist", "pnp-z", "lidar-z", "delta-z", "distance", "plane", "bearing",
                       "depth-mean", "depth-confidence", "depth-neighbors", "rms", "decision-margin", "hamming",
                       "edge", "analysis-rate", "frame-age", "compute-time", "height", "height-source", "kalman",
                       "tag-id", "status", "units"]
        for anchor in anchors {
            let url = try XCTUnwrap(TagMetricGlossaryViewController.documentURL(anchor: anchor))
            XCTAssertTrue(url.isFileURL, "Glossary definitions must be available offline")
            XCTAssertEqual(url.fragment, anchor)
            let document = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(document.contains("id=\"\(anchor)\""), "Missing glossary definition: \(anchor)")
        }
        let url = try XCTUnwrap(TagMetricGlossaryViewController.documentURL(anchor: "tilt"))
        let directory = url.deletingLastPathComponent().appendingPathComponent("diagrams")
        let diagrams = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertGreaterThanOrEqual(diagrams.filter { $0.pathExtension == "svg" }.count, 3)
    }

    func testTermSheetLoadsDiagramDeepLinkAndDoneReturnsToExpandedReadout() throws {
        let source = try XCTUnwrap(window.rootViewController)
        let panel = TagDebugPanelView(frame: CGRect(x: 0, y: 100, width: 390, height: 290))
        panel.setExpanded(true)
        source.view.addSubview(panel)
        TagMetricGlossaryViewController.present(anchor: "tilt", from: panel)
        let sheet = try XCTUnwrap(source.presentedViewController as? UINavigationController)
        let glossary = try XCTUnwrap(sheet.topViewController as? TagMetricGlossaryViewController)
        glossary.loadViewIfNeeded()
        let loaded = expectation(description: "Bundled glossary loaded")
        var didFinish = false
        let loading = glossary.webView.observe(\.isLoading, options: [.initial, .new]) { webView, _ in
            if !webView.isLoading && webView.url != nil && !didFinish {
                didFinish = true
                loaded.fulfill()
            }
        }
        wait(for: [loaded], timeout: 20)
        loading.invalidate()
        let rendered = try XCTUnwrap(try evaluate("""
            ({ fragment: location.hash,
               heading: document.getElementById('tilt') !== null,
               pictures: Array.from(document.images).map(image => ({
                 loaded: image.complete && image.naturalWidth > 0,
                 description: image.alt,
                 local: new URL(image.src).protocol === 'file:'
               })) })
            """, in: glossary.webView) as? [String: Any])
        XCTAssertEqual(rendered["fragment"] as? String, "#tilt")
        XCTAssertEqual(rendered["heading"] as? Bool, true)
        let pictures = try XCTUnwrap(rendered["pictures"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(pictures.count, 3)
        for picture in pictures {
            XCTAssertEqual(picture["loaded"] as? Bool, true, "Bundled diagram must render")
            XCTAssertEqual(picture["local"] as? Bool, true)
            XCTAssertFalse((picture["description"] as? String ?? "").isEmpty, "Each diagram needs accessible alt text")
        }
        let position = try evaluate("document.getElementById('tilt').getBoundingClientRect().top", in: glossary.webView) as? Double
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(position), -1, "Deep link must scroll to the requested definition")
        XCTAssertLessThanOrEqual(try XCTUnwrap(position), 60, "Deep link must scroll to the requested definition")
        try savePNG("glossary-tilt-offline", webView: glossary.webView)
        let done = try XCTUnwrap(glossary.navigationItem.leftBarButtonItem)
        XCTAssertEqual(done.accessibilityIdentifier, "tagMetricGlossaryDone")
        let action = try XCTUnwrap(done.action)
        UIApplication.shared.sendAction(action, to: done.target, from: done, for: nil)
        let dismissed = expectation(description: "Glossary dismissed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismissed.fulfill() }
        wait(for: [dismissed], timeout: 2)
        XCTAssertNil(source.presentedViewController)
        XCTAssertTrue(panel.isExpanded, "Closing help must retain the expanded details state")
        XCTAssertTrue(panel.superview === source.view)
    }
}
