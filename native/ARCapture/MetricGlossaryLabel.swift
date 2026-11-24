import UIKit

/// Keeps the native readout's typography while giving each term its own link and VoiceOver target.
final class MetricGlossaryLabel: UILabel {
    struct Link {
        let title: String
        let anchor: String
        let expression: NSRegularExpression

        init(_ title: String, anchor: String, pattern: String? = nil) {
            self.title = title
            self.anchor = anchor
            expression = try! NSRegularExpression(pattern: pattern ?? NSRegularExpression.escapedPattern(for: title))
        }
    }

    private final class LinkButton: UIButton {
        var activate: (() -> Void)?
        override func accessibilityActivate() -> Bool {
            guard !isHidden, isEnabled else { return false }
            activate?()
            return true
        }
    }

    private var links: [Link]
    private var buttons = [LinkButton]()
    private var ranges = [NSRange?]()
    private var accessibilityValues = [String: String]()
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private var isUpdatingLinks = false
    var onOpenGlossary: ((String) -> Void)?
    var linkColor: UIColor? = .systemCyan { didSet { updateLinks() } }
    var linksEnabled = true {
        didSet { if oldValue != linksEnabled { updateLinks() } }
    }

    override var text: String? { didSet { updateLinks() } }
    override var font: UIFont! { didSet { updateLinks() } }
    override var textColor: UIColor! { didSet { updateLinks() } }

    init(links: [Link]) {
        self.links = links
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        for (index, link) in links.enumerated() {
            let button = LinkButton(type: .custom)
            button.accessibilityIdentifier = "tagMetricHelp-" + link.anchor
            button.accessibilityLabel = "Definition of " + link.title
            button.accessibilityHint = "Opens the glossary at this term, with explanations and diagrams"
            button.accessibilityTraits = [.link]
            button.activate = { [weak self] in
                guard let self else { return }
                self.onOpenGlossary?(self.links[index].anchor)
            }
            button.addTarget(self, action: #selector(openLink(_:)), for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
        updateLinks()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A convention change changes link semantics without allocating a new readout hierarchy.
    func setLinks(_ definitions: [Link]) {
        precondition(definitions.count == buttons.count)
        links = definitions
        for (index, link) in links.enumerated() {
            buttons[index].accessibilityIdentifier = "tagMetricHelp-" + link.anchor
            buttons[index].accessibilityLabel = "Definition of " + link.title
        }
        updateLinks()
    }

    @objc private func openLink(_ sender: UIButton) {
        guard let index = buttons.firstIndex(where: { $0 === sender }) else { return }
        onOpenGlossary?(links[index].anchor)
    }

    /// Rich readout semantics (including unavailable reasons) must follow the term into its link.
    func setAccessibilityValue(_ value: String, for anchor: String) {
        accessibilityValues[anchor] = value
        for (index, link) in links.enumerated() where link.anchor == anchor {
            buttons[index].accessibilityValue = value
        }
    }

    private func updateLinks() {
        guard buttons.count == links.count, !isUpdatingLinks else { return }
        isUpdatingLinks = true
        defer { isUpdatingLinks = false }
        let string = text ?? ""
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        let attributed = NSMutableAttributedString(string: string, attributes: [
            .font: font ?? UIFont.systemFont(ofSize: 12), .foregroundColor: textColor ?? UIColor.white
        ])
        ranges = links.map { $0.expression.firstMatch(in: string, range: fullRange)?.range }
        for (index, range) in ranges.enumerated() {
            buttons[index].isHidden = !linksEnabled || range == nil
            if linksEnabled, let range {
                // Preserve the current reading when a formerly static inline label becomes a link.
                let nsString = string as NSString
                let before = nsString.substring(to: range.location)
                let after = nsString.substring(from: range.location + range.length)
                let prefix = before.components(separatedBy: CharacterSet(charactersIn: "·\n")).last ?? ""
                let suffix = after.components(separatedBy: CharacterSet(charactersIn: "·\n")).first ?? ""
                buttons[index].accessibilityValue = accessibilityValues[links[index].anchor]
                    ?? (prefix + nsString.substring(with: range) + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
                attributed.addAttributes([.foregroundColor: linkColor ?? textColor ?? UIColor.white,
                                          .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
            }
        }
        // Keep the original label/value available in compact mode. Expanded terms are individual links.
        isAccessibilityElement = !linksEnabled || !ranges.contains(where: { $0 != nil })
        attributedText = attributed
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard linksEnabled, bounds.width > 0, bounds.height > 0 else { return }
        let string = text ?? ""
        let baseFont = font ?? UIFont.systemFont(ofSize: 12)
        let naturalWidth = string.components(separatedBy: "\n").map {
            ($0 as NSString).size(withAttributes: [.font: baseFont]).width
        }.max() ?? 0
        let scale = adjustsFontSizeToFitWidth && naturalWidth > bounds.width
            ? max(minimumScaleFactor, bounds.width / naturalWidth) : 1
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = lineBreakMode
        textStorage.setAttributedString(NSAttributedString(string: string, attributes: [
            .font: baseFont.withSize(baseFont.pointSize * scale), .paragraphStyle: paragraph
        ]))
        textContainer.size = bounds.size
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let yOffset = (bounds.height - usedRect.height) / 2 - usedRect.minY
        for (index, range) in ranges.enumerated() {
            guard let range, !buttons[index].isHidden else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            rect.origin.y += yOffset
            rect = rect.insetBy(dx: -2, dy: -2).intersection(bounds)
            buttons[index].frame = rect.isNull ? .zero : rect.integral.intersection(bounds)
            buttons[index].isHidden = buttons[index].frame.isEmpty
        }
    }
}
