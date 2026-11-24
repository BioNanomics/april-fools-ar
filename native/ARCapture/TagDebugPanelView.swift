import UIKit

/// Native, reusable readouts. Frame-critical updates never cross the JS bridge.
final class TagDebugPanelView: UIView {
    private(set) var isExpanded = false
    var preferredHeight: CGFloat { isExpanded ? 290 : 44 }
    var onPreferredHeightChanged: ((CGFloat) -> Void)?
    var onOpenGlossary: ((String) -> Void)?
    private let titleLabel = MetricGlossaryLabel(links: [
        .init("Tag ID", anchor: "tag-id", pattern: "TAG(?: #\\d+| DEBUG)?"),
        .init("Status", anchor: "status", pattern: "(?<= · )[^\\n]+"),
        .init("Height", anchor: "height", pattern: "↑|Height"),
        .init("Height units", anchor: "units", pattern: "cm")
    ])
    private let detailsButton = UIButton(type: .system)
    private let metricsScrollView = UIScrollView()
    private let translationRow = DebugMetricRow(titles: ["X right · m", "Y down · m", "Z forward · m"],
        anchors: ["x-right", "y-down", "z-forward"], valueSize: 19)
    private let rotationRow = DebugMetricRow(titles: ["Cam roll · °", "Cam pitch · °", "Cam yaw · °"],
        anchors: ["camera-roll", "camera-pitch", "camera-yaw"], valueSize: 18)
    private let gravityOrientationLabel = MetricGlossaryLabel(links: [
        .init("Gravity", anchor: "gravity"), .init("Tilt", anchor: "tilt"), .init("Twist", anchor: "twist")
    ])
    private let depthRow = DebugMetricRow(titles: ["PnP Z · m", "LiDAR Z · m", "|Δ Z| · m"],
        anchors: ["pnp-z", "lidar-z", "delta-z"], valueSize: 21)
    private let geometryRow = DebugMetricRow(titles: ["Distance · m", "Plane · °", "Bearing · °"],
        anchors: ["distance", "plane", "bearing"], valueSize: 18)
    private let meanLabel = MetricGlossaryLabel(links: [
        .init("3×3 mean", anchor: "depth-mean"),
        .init("Depth confidence", anchor: "depth-confidence", pattern: "LOW|MED|HIGH|(?<=m · )[—?]"),
        .init("Valid depth neighbors", anchor: "depth-neighbors", pattern: "[0-9—]+/9"),
        .init("Tag width preset", anchor: "edge", pattern: "preset"),
        .init("Measured tag width", anchor: "edge", pattern: "measured width"),
        .init("Tag width settings", anchor: "edge", pattern: "Settings")
    ])
    private let qualityLabel = MetricGlossaryLabel(links: [
        .init("RMS", anchor: "rms"), .init("Decision margin", anchor: "decision-margin", pattern: "margin"),
        .init("Hamming corrected bits", anchor: "hamming", pattern: "(?<= · )H")
    ])
    private let rateLabel = MetricGlossaryLabel(links: [
        .init("Edge", anchor: "edge"),
        .init("Tag width source", anchor: "edge", pattern: "Field Auto|Auto|AR estimate|manual"),
        .init("Field type", anchor: "edge", pattern: "(?:FRC|FTC)(?:/FTC)?"),
        .init("Competition year", anchor: "edge", pattern: "[0-9]{4}"),
        .init("Analysis rate", anchor: "analysis-rate", pattern: "Hz"),
        .init("Frame age", anchor: "frame-age", pattern: "(?:Frame age|Age|age)"),
        .init("Compute time", anchor: "compute-time", pattern: "compute"),
        .init("Height source", anchor: "height-source", pattern: "LiDAR|Pose"),
        .init("Height", anchor: "height", pattern: "height"), .init("Kalman", anchor: "kalman")
    ])
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
        titleLabel.linkColor = nil // Keep validity colors while underlines identify title links.
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        meanLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        qualityLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        gravityOrientationLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        gravityOrientationLabel.accessibilityIdentifier = "tagDebugGravityOrientation"
        [meanLabel, qualityLabel, gravityOrientationLabel].forEach {
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
        [translationRow, rotationRow, gravityOrientationLabel, depthRow, geometryRow, meanLabel, qualityLabel].forEach(metricsScrollView.addSubview)
        detailsButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        detailsButton.tintColor = .white
        detailsButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        detailsButton.layer.cornerRadius = 8
        detailsButton.accessibilityIdentifier = "tagDebugDetailsButton"
        detailsButton.addTarget(self, action: #selector(toggleDetails), for: .touchUpInside)
        addSubview(detailsButton)
        for label in glossaryLabels {
            label.onOpenGlossary = { [weak self] anchor in self?.openGlossary(anchor) }
        }
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
        let rows: [(UIView, CGFloat)] = [(translationRow, 36), (rotationRow, 34), (gravityOrientationLabel, 17),
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
    private var glossaryLabels: [MetricGlossaryLabel] {
        [titleLabel, gravityOrientationLabel, meanLabel, qualityLabel, rateLabel]
            + [translationRow, rotationRow, depthRow, geometryRow].flatMap(\.headings)
    }
    private func openGlossary(_ anchor: String) {
        if let onOpenGlossary { onOpenGlossary(anchor) }
        else { TagMetricGlossaryViewController.present(anchor: anchor, from: self) }
    }
    private func updateExpansion() {
        glossaryLabels.forEach { $0.linksEnabled = isExpanded }
        [translationRow, rotationRow, gravityOrientationLabel, depthRow, geometryRow, meanLabel, qualityLabel].forEach { $0.isHidden = !isExpanded }
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
        titleLabel.setAccessibilityValue(titleAccessibilityText, for: "status")
        titleLabel.setAccessibilityValue(titleAccessibilityText, for: "height")
    }
    /// Links own their taps; values and background still pass through to tag selection.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        let localPoint = detailsButton.convert(point, from: self)
        if detailsButton.point(inside: localPoint, with: event) {
            return detailsButton.hitTest(localPoint, with: event)
        }
        if isExpanded {
            if let hit = super.hitTest(point, with: event), hit is UIControl { return hit }
            let scrollPoint = metricsScrollView.convert(point, from: self)
            if metricsScrollView.isScrollEnabled && metricsScrollView.bounds.contains(scrollPoint) {
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
        showGravityOrientation(nil, unavailableReason: reason)
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
            let edge: String
            if settings.tagSizeMode == "auto" { edge = "Field Auto" }
            else if settings.tagSizeMode == "ftc" || settings.tagSizeMode == "frc" { edge = "\(settings.tagSizeMode.uppercased()) \(settings.competitionYear)" }
            else { edge = String(format: "Edge %.1f mm", settings.tagSizeMeters * 1000) }
            expandedRateText = String(format: "%@ · %.1f Hz\nFrame age %.0f ms · compute %.0f ms", edge,
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
            "trackingLimited": "TRACKING LIMITED", "poseUnavailable": "POSE UNAVAILABLE", "sizeUnavailable": "SET TAG SIZE"]
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
        showGravityOrientation(debug["gravityOrientation"] as? [String: Any])
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
        let resolution = debug["tagSizeResolution"] as? [String: Any]
        let width = resolution?["status"] as? String == "unavailable" ? nil :
            (TagDebugMath.number(debug["tagSizeMeters"]) ?? TagDebugMath.number(resolution?["tagSizeMeters"])
                ?? (settings.tagSizeMode == "auto" ? nil : settings.tagSizeMeters))
        let sourceKey = debug["tagSizeSource"] as? String ?? settings.tagSizeSource
        let source: String
        if sourceKey == "sceneDepth-standard-match" {
            let label = resolution?["label"] as? String ?? ""
            source = label.contains("FRC") ? "Auto · FRC/FTC" : "Auto · FTC"
        } else if settings.tagSizeMode == "auto" { source = "Auto" }
        else if sourceKey == "ar-two-point-edge" { source = "AR estimate" }
        else if sourceKey == "ftc-default" || sourceKey == "frc-default" {
            source = "\(settings.tagSizeMode.uppercased()) \(settings.competitionYear)"
        }
        else { source = "manual" }
        let edge = width.map { String(format: "Edge %.1f mm (%@)", $0 * 1000, source) } ?? "Edge — (\(source))"
        expandedRateText = String(format: "%@ · %.1f Hz\nAge %.0f ms · compute %.0f ms", edge,
            analysisHz.isFinite ? analysisHz : 0, max(0, age) * 1000, latencyMilliseconds ?? 0)
        if status == "sizeUnavailable" { meanLabel.text = "Choose a preset or measured width in Settings" }
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

    private func showGravityOrientation(_ record: [String: Any]?, unavailableReason: String? = nil) {
        let record = record ?? [:]
        let rawAvailable = record["available"] as? NSNumber
        let available = rawAvailable.map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
        func angle(_ key: String, range: ClosedRange<Double>) -> Double? {
            guard available, let value = record[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, range.contains(value.doubleValue) else { return nil }
            return value.doubleValue
        }
        let tilt = angle("tiltFromVerticalDegrees", range: 0...90)
        let twist = tilt == nil ? nil : angle("twistDegrees", range: -180...180)
        let tiltText = tilt.map { String(format: "%.1f°", $0 == 0 ? 0 : $0) } ?? "—"
        let twistText = twist.map { String(format: "%+.1f°", $0 == 0 ? 0 : $0) } ?? "—"
        gravityOrientationLabel.text = "Gravity · Tilt \(tiltText) · Twist \(twistText)"
        let reason = unavailableReason ?? (record["reason"] as? String) ?? "No gravity-relative orientation in this frame"
        let tiltAccessibility = tilt.map { "Tilt from vertical \(String(format: "%.1f", $0)) degrees; zero degrees is a vertical tag plane." }
            ?? "Tilt from vertical unavailable. Reason: \(available ? "Invalid gravity-relative orientation" : reason)."
        let twistReason = tilt.map { $0 > 89.99 } == true
            ? "Gravity does not define upright within a horizontal tag plane."
            : "Reason: \(available ? "No valid twist in this frame" : reason)."
        let twistAccessibility = twist.map { "Twist from upright \(String(format: "%+.1f", $0)) degrees; positive is clockwise when viewing the printed front." }
            ?? "Twist from upright unavailable. \(twistReason)"
        gravityOrientationLabel.accessibilityLabel = "Gravity-relative tag orientation"
        gravityOrientationLabel.accessibilityValue = tiltAccessibility + " " + twistAccessibility
        gravityOrientationLabel.setAccessibilityValue(tiltAccessibility, for: "tilt")
        gravityOrientationLabel.setAccessibilityValue(twistAccessibility, for: "twist")
    }
}

private final class DebugMetricRow: UIView {
    private(set) var headings = [MetricGlossaryLabel]()
    private var values = [UILabel]()
    init(titles: [String], anchors: [String], valueSize: CGFloat) {
        super.init(frame: .zero)
        for (title, anchor) in zip(titles, anchors) {
            let heading = MetricGlossaryLabel(links: [.init(title.components(separatedBy: " · ")[0], anchor: anchor,
                pattern: NSRegularExpression.escapedPattern(for: title))])
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
