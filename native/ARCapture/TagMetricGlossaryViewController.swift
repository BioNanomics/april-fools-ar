import UIKit
import WebKit
import SafariServices

/// An offline, section-linked reference generated from docs/tag-metric-glossary.md.
final class TagMetricGlossaryViewController: UIViewController, WKNavigationDelegate {
    private let anchor: String
    private let resourceBundle: Bundle
    private(set) var webView: WKWebView!
    private var historyObservation: NSKeyValueObservation?
    private lazy var backButton = UIBarButtonItem(title: "Back", style: .plain,
                                                  target: self, action: #selector(goBack))

    init(anchor: String, bundle: Bundle = .main) {
        self.anchor = anchor
        resourceBundle = bundle
        super.init(nibName: nil, bundle: nil)
        title = "Measurement glossary"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func documentURL(anchor: String, bundle: Bundle = .main) -> URL? {
        guard let file = bundle.url(forResource: "index", withExtension: "html", subdirectory: "MetricGlossary"),
              var components = URLComponents(url: file, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = anchor
        return components.url
    }

    static func present(anchor: String, from sourceView: UIView) {
        var responder: UIResponder? = sourceView
        while responder != nil && !(responder is UIViewController) { responder = responder?.next }
        guard var presenter = (responder as? UIViewController) ?? sourceView.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let controller = TagMetricGlossaryViewController(anchor: anchor)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        presenter.present(navigation, animated: true)
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.accessibilityIdentifier = "tagMetricGlossaryWebView"
        webView.allowsBackForwardNavigationGestures = true
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                          target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "tagMetricGlossaryDone"
        let contentsButton = UIBarButtonItem(title: "Contents", style: .plain,
                                             target: self, action: #selector(showContents))
        contentsButton.accessibilityIdentifier = "tagMetricGlossaryContents"
        backButton.accessibilityIdentifier = "tagMetricGlossaryBack"
        navigationItem.rightBarButtonItems = [contentsButton, backButton]
        historyObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
            self?.backButton.isEnabled = webView.canGoBack
        }
        guard let document = Self.documentURL(anchor: anchor, bundle: resourceBundle) else {
            let message = UILabel()
            message.text = "The measurement glossary could not be loaded."
            message.numberOfLines = 0
            message.textAlignment = .center
            message.font = .preferredFont(forTextStyle: .body)
            message.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(message)
            NSLayoutConstraint.activate([
                message.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                message.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                message.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
            ])
            return
        }
        webView.loadFileURL(document, allowingReadAccessTo: document.deletingLastPathComponent())
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func goBack() { webView.goBack() }
    @objc private func showContents() {
        guard let url = Self.documentURL(anchor: "overview", bundle: resourceBundle) else { return }
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Native deep links should land at the selected heading even when SVG
        // layout changes the page height while the file loads.
        let currentAnchor = webView.url?.fragment ?? anchor
        guard let encoded = try? JSONSerialization.data(withJSONObject: [currentAnchor]),
              let json = String(data: encoded, encoding: .utf8) else { return }
        webView.evaluateJavaScript("""
            (() => {
                const target = document.getElementById(\(json)[0]);
                if (!target) return false;
                target.scrollIntoView();
                let heading = /^H[1-6]$/.test(target.tagName) ? target : target.nextElementSibling;
                while (heading && heading.tagName === 'A' && heading.hasAttribute('id')) {
                    heading = heading.nextElementSibling;
                }
                if (heading && /^H[1-6]$/.test(heading.tagName)) heading.focus({preventScroll: true});
                return true;
            })()
            """, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let document = Self.documentURL(anchor: "", bundle: resourceBundle)
        if url.isFileURL && url.path == document?.path {
            decisionHandler(.allow)
        } else if navigationAction.navigationType == .linkActivated,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.cancel)
            present(SFSafariViewController(url: url), animated: true)
        } else {
            decisionHandler(.cancel)
        }
    }
}
