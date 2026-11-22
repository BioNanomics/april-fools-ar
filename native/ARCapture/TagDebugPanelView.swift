import UIKit

/// Native, reusable readouts. Frame-critical updates never cross the JS bridge.
final class TagDebugPanelView: UIView {
    private(set) var isExpanded = false
    var preferredHeight: CGFloat { isExpanded ? 270 : 44 }
    var onPreferredHeightChanged: ((CGFloat) -> Void)?
    private let titleLabel = UILabel()
    private let detailsButton = UIButton(type: .system)
    private let metricsScrollView = UIScrollView()
    private let translationRow = DebugMetricRow(titles: ["X right · m", "Y down · m", "Z forward · m"], valueSize: 19)
    private let rotationRow = DebugMetricRow(titles: ["Roll · °", "Pitch · °", "Yaw · °"], valueSize: 18)
    private let depthRow = DebugMetricRow(titles: ["PnP Z · m", "LiDAR Z · m", "|Δ Z| · m"], valueSize: 21)
    private let geometryRow = DebugMetricRow(titles: ["Distance · m", "Plane · °", "Bearing · °"], valueSize: 18)
    private let meanLabel = UILabel()
    private let qualityLabel = UILabel()
    private let rateLabel = UILabel()
    private var compactRateText = "No current tag measurement"
    private var expandedRateText = "No current tag measurement"
    private var compactTitleText = "TAG DEBUG · WAITING"
    private var expandedTitleText = "TAG DEBUG · WAITING"
    private var titleAccessibilityText = "TAG DEBUG · WAITING"
    private var expiryToken: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 12
        layer.borderWidth = 1
        isUserInteractionEnabled = true
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        meanLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        qualityLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        [meanLabel, qualityLabel].forEach {
            $0.textColor = .white
            $0.adjustsFontSizeToFitWidth = true
            $0.minimumScaleFactor = 0.85
        }
        rateLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        rateLabel.textColor = .lightGray
        rateLabel.adjustsFontSizeToFitWidth = true
        rateLabel.minimumScaleFactor = 0.8
        addSubview(titleLabel)
        addSubview(rateLabel)
        metricsScrollView.accessibilityIdentifier = "tagDebugMetrics"
        metricsScrollView.alwaysBounceVertical = false
        metricsScrollView.showsHorizontalScrollIndicator = false
        metricsScrollView.contentInsetAdjustmentBehavior = .never
        addSubview(metricsScrollView)
        [translationRow, rotationRow, depthRow, geometryRow, meanLabel, qualityLabel].forEach(metricsScrollView.addSubview)
        detailsButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        detailsButton.tintColor = .white
        detailsButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        detailsButton.layer.cornerRadius = 8
        detailsButton.accessibilityIdentifier = "tagDebugDetailsButton"
        detailsButton.addTarget(self, action: #selector(toggleDetails), for: .touchUpInside)
        addSubview(detailsButton)
        updateExpansion()
        showUnavailable("Waiting for a visible tag")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, bounds.width - 24)
        detailsButton.frame = CGRect(x: max(12, bounds.width - 100), y: 0, width: 88, height: 44)
        if !isExpanded {
            titleLabel.frame = CGRect(x: 12, y: 3, width: max(0, width - 96), height: 21)
            rateLabel.frame = CGRect(x: 12, y: 24, width: max(0, width - 96), height: 14)
            return
        }
        titleLabel.frame = CGRect(x: 12, y: 8, width: max(0, width - 96), height: 42)
        metricsScrollView.frame = CGRect(x: 0, y: 52, width: bounds.width, height: max(0, bounds.height - 54))
        let rows: [(UIView, CGFloat)] = [(translationRow, 36), (rotationRow, 34),
            (depthRow, 38), (geometryRow, 34), (meanLabel, 17), (qualityLabel, 17), (rateLabel, 28)]
        var y: CGFloat = 0
        for (view, height) in rows {
            view.frame = CGRect(x: 12, y: y, width: width, height: height)
            y += height + 2
        }
        metricsScrollView.contentSize = CGSize(width: bounds.width, height: max(0, y - 2))
        metricsScrollView.isScrollEnabled = metricsScrollView.contentSize.height > metricsScrollView.bounds.height + 0.5
        let maximumOffset = max(0, metricsScrollView.contentSize.height - metricsScrollView.bounds.height)
        metricsScrollView.contentOffset.y = max(0, min(metricsScrollView.contentOffset.y, maximumOffset))
    }
    /// Keep the readout legible without stretching across a tablet or covering a short camera viewport.
    static func overlayFrame(in viewport: CGRect, preferredHeight: CGFloat) -> CGRect {
        let width = min(480, max(0, viewport.width - 16))
        let availableHeight = max(0, viewport.height - 16)
        let height = min(preferredHeight, min(availableHeight, max(44, viewport.height - 88)))
        return CGRect(x: viewport.minX + 8, y: viewport.maxY - height - 8, width: width, height: height)
    }
    /// The host keeps the camera full size and lays out this overlay using preferredHeight.
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        updateExpansion()
        onPreferredHeightChanged?(preferredHeight)
    }
    @objc private func toggleDetails() { setExpanded(!isExpanded) }
    private func updateExpansion() {
        [translationRow, rotationRow, depthRow, geometryRow, meanLabel, qualityLabel].forEach { $0.isHidden = !isExpanded }
        metricsScrollView.isHidden = !isExpanded
        if isExpanded { metricsScrollView.addSubview(rateLabel) }
        else { addSubview(rateLabel); metricsScrollView.contentOffset = .zero }
        titleLabel.font = .monospacedSystemFont(ofSize: isExpanded ? 15 : 12, weight: .regular)
        titleLabel.numberOfLines = isExpanded ? 2 : 1
        let title = isExpanded ? "Collapse" : "Details"
        detailsButton.setTitle(title, for: .normal)
        detailsButton.accessibilityLabel = title
        detailsButton.accessibilityHint = isExpanded ? "Show the compact tag readout" : "Show all tag debug metrics"
        rateLabel.numberOfLines = isExpanded ? 2 : 1
        updateTitleText()
        updateRateText()
        setNeedsLayout()
    }
    private func updateRateText() { rateLabel.text = isExpanded ? expandedRateText : compactRateText }
    private func updateTitleText() {
        titleLabel.text = isExpanded ? expandedTitleText : compactTitleText
        titleLabel.accessibilityLabel = titleAccessibilityText
    }
    /// Readout taps pass through unless a constrained expanded panel needs scrolling.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        let localPoint = detailsButton.convert(point, from: self)
        if detailsButton.point(inside: localPoint, with: event) {
            return detailsButton.hitTest(localPoint, with: event)
        }
        if isExpanded && metricsScrollView.isScrollEnabled {
            let scrollPoint = metricsScrollView.convert(point, from: self)
            if metricsScrollView.bounds.contains(scrollPoint) {
                return metricsScrollView.hitTest(scrollPoint, with: event)
            }
        }
        return nil
    }
    static func color(_ severity: String) -> UIColor {
        switch severity {
        case "good": return .systemGreen
        case "warning": return .systemYellow
        case "bad": return .systemRed
        default: return .lightGray
        }
    }
    func showUnavailable(_ reason: String) {
        expiryToken = nil
        compactTitleText = "TAG DEBUG · WAITING"
        expandedTitleText = compactTitleText
        titleAccessibilityText = compactTitleText
        updateTitleText()
        titleLabel.textColor = .lightGray
        layer.borderColor = UIColor.darkGray.cgColor
        [translationRow, rotationRow, depthRow, geometryRow].forEach { $0.setValues(["—", "—", "—"]) }
        meanLabel.text = reason
        qualityLabel.text = "Point at a tag · tap its outline to select"
        compactRateText = "No current tag measurement"
        expandedRateText = compactRateText
        updateRateText()
    }
    func show(debug: [String: Any]?, frameID: String, timestamp: Double, analysisHz: Double,
              latencyMilliseconds: Double?, settings: TagDebugSettings) {
        let age = ProcessInfo.processInfo.systemUptime - timestamp
        guard age.isFinite, age <= 0.4 else { showUnavailable("Stale result · waiting for a current frame"); return }
        guard let debug else {
            showUnavailable("No tag in the current camera frame")
            expandedRateText = String(format: "Edge %.1f mm · %.1f Hz\nFrame age %.0f ms · compute %.0f ms", settings.tagSizeMeters * 1000,
                analysisHz.isFinite ? analysisHz : 0, max(0, age) * 1000, latencyMilliseconds ?? 0)
            compactRateText = String(format: "%.1f Hz · age %.0f ms", analysisHz.isFinite ? analysisHz : 0,
                max(0, age) * 1000)
            updateRateText()
            return
        }
        expiryToken = frameID
        let severity = debug["severity"] as? String ?? "neutral"
        let status = debug["status"] as? String ?? "poseUnavailable"
        let titles = ["valid": "VALID", "tooFar": "TOO FAR", "badAngle": "BAD ANGLE",
            "depthMismatch": severity == "warning" ? "CHECK DEPTH" : "DEPTH MISMATCH",
            "missingDepth": "MISSING DEPTH", "ambiguous": "AMBIGUOUS", "lowConfidence": "LOW CONFIDENCE",
            "trackingLimited": "TRACKING LIMITED", "poseUnavailable": "POSE UNAVAILABLE"]
        let id = (debug["id"] as? NSNumber)?.intValue ?? -1
        compactTitleText = "TAG #\(id) · \(titles[status] ?? status.uppercased())"
        expandedTitleText = compactTitleText
        var heightSource: String?
        if let height = debug["floorHeight"] as? [String: Any] {
            let detail: String
            if height["available"] as? Bool == true,
               let raw = height["meters"] as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID(),
               raw.doubleValue.isFinite, raw.doubleValue >= 0, raw.doubleValue <= 30,
               let sourceKey = height["source"] as? String,
               let source = ["sceneDepth": "LiDAR", "tagPose": "Pose"][sourceKey],
               let formatted = HeightDisplayFormatter.string(meters: raw.doubleValue, showImperial: settings.showImperialHeight) {
                detail = "↑ ≈\(formatted)"
                heightSource = source
            } else {
                detail = height["reason"] as? String == "floorNotSelected" ? "Height — · set floor" : "Height — · unavailable"
            }
            expandedTitleText += "\n" + detail
            titleLabel.isAccessibilityElement = true
        }
        titleAccessibilityText = expandedTitleText
        if let heightSource { titleAccessibilityText += ". Height source: \(heightSource)." }
        updateTitleText()
        titleLabel.textColor = Self.color(severity)
        layer.borderColor = Self.color(severity).cgColor
        func scalar(_ key: String, _ format: String = "%.3f") -> String {
            TagDebugMath.number(debug[key]).map { String(format: format, $0) } ?? "—"
        }
        func triple(_ key: String, _ format: String) -> [String] {
            TagDebugMath.numbers(debug[key], count: 3)?.map { String(format: format, $0) } ?? ["—", "—", "—"]
        }
        translationRow.setValues(triple("translationMeters", "%+.3f"))
        rotationRow.setValues(triple("eulerDegrees", "%+.1f"))
        depthRow.setValues([scalar("opticalPoseZMeters"), scalar("centerDepthMeters"), scalar("depthDifferenceMeters")])
        var deltaColor = UIColor.lightGray
        if let delta = TagDebugMath.number(debug["depthDifferenceMeters"]) {
            deltaColor = Self.color(delta > settings.rejectDepthDifferenceMeters + 1e-9 ? "bad" :
                (delta > settings.warningDepthDifferenceMeters + 1e-9 ? "warning" : "good"))
        }
        depthRow.setColor(deltaColor, at: 2)
        geometryRow.setValues([scalar("rangeMeters"), scalar("planeAngleDegrees", "%.1f"), scalar("centerBearingDegrees", "%.1f")])
        geometryRow.setColor((TagDebugMath.number(debug["rangeMeters"]) ?? 0) > settings.maxDistanceMeters ? .systemRed : .white, at: 0)
        geometryRow.setColor((TagDebugMath.number(debug["planeAngleDegrees"]) ?? 0) > settings.maxPlaneAngleDegrees ? .systemRed : .white, at: 1)
        let confidence = (debug["centerConfidence"] as? NSNumber)?.intValue
        let confidenceText = confidence.map { ["LOW", "MED", "HIGH"].indices.contains($0) ? ["LOW", "MED", "HIGH"][$0] : "?" } ?? "—"
        meanLabel.text = "3×3 mean \(scalar("meanDepthMeters")) m · \(confidenceText) · \(scalar("validNeighborCount", "%.0f"))/9"
        qualityLabel.text = "RMS \(scalar("reprojectionRMSEPixels", "%.2f"))px · margin \(scalar("decisionMargin", "%.1f")) · H\(scalar("hamming", "%.0f"))"
        let source = settings.tagSizeSource == "ar-two-point-edge" ? "AR estimate" : (settings.tagSizeSource == "frc-default" ? "FRC" : "manual")
        expandedRateText = String(format: "Edge %.1f mm (%@) · %.1f Hz\nAge %.0f ms · compute %.0f ms", settings.tagSizeMeters * 1000,
            source, analysisHz.isFinite ? analysisHz : 0, max(0, age) * 1000, latencyMilliseconds ?? 0)
        compactRateText = String(format: "%.1f Hz · age %.0f ms", analysisHz.isFinite ? analysisHz : 0,
            max(0, age) * 1000)
        if let heightSource {
            compactRateText = "\(heightSource) height · " + compactRateText
            expandedRateText += " · \(heightSource) height"
        }
        updateRateText()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.4 - age)) { [weak self] in
            guard let self, self.expiryToken == frameID else { return }
            self.showUnavailable("Stale result · waiting for a current frame")
        }
    }
}

private final class DebugMetricRow: UIView {
    private var headings = [UILabel]()
    private var values = [UILabel]()
    init(titles: [String], valueSize: CGFloat) {
        super.init(frame: .zero)
        for title in titles {
            let heading = UILabel()
            heading.text = title
            heading.font = .systemFont(ofSize: 10, weight: .medium)
            heading.textColor = .lightGray
            let value = UILabel()
            value.font = .monospacedSystemFont(ofSize: valueSize, weight: .semibold)
            value.textColor = .white
            value.adjustsFontSizeToFitWidth = true
            value.minimumScaleFactor = 0.85
            addSubview(heading); addSubview(value)
            headings.append(heading); values.append(value)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / 3
        for index in 0..<3 {
            headings[index].frame = CGRect(x: CGFloat(index) * width, y: 0, width: width - 5, height: 12)
            values[index].frame = CGRect(x: CGFloat(index) * width, y: 12, width: width - 5, height: max(0, bounds.height - 12))
        }
    }
    func setValues(_ texts: [String]) {
        for index in 0..<3 { values[index].text = texts[index]; values[index].textColor = .white }
    }
    func setColor(_ color: UIColor, at index: Int) { values[index].textColor = color }
}
