import UIKit

/// Native, reusable readouts. Frame-critical updates never cross the JS bridge.
final class TagDebugPanelView: UIView {
    private let titleLabel = UILabel()
    private let translationRow = DebugMetricRow(titles: ["X right · m", "Y down · m", "Z forward · m"], valueSize: 19)
    private let rotationRow = DebugMetricRow(titles: ["Roll · °", "Pitch · °", "Yaw · °"], valueSize: 18)
    private let depthRow = DebugMetricRow(titles: ["PnP Z · m", "LiDAR Z · m", "|Δ Z| · m"], valueSize: 21)
    private let geometryRow = DebugMetricRow(titles: ["Range · m", "Plane · °", "Bearing · °"], valueSize: 18)
    private let meanLabel = UILabel()
    private let qualityLabel = UILabel()
    private let rateLabel = UILabel()
    private var expiryToken: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.94)
        layer.cornerRadius = 12
        layer.borderWidth = 2
        isUserInteractionEnabled = false
        titleLabel.font = .monospacedSystemFont(ofSize: 19, weight: .bold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        meanLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        qualityLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        [meanLabel, qualityLabel].forEach {
            $0.textColor = .white
            $0.adjustsFontSizeToFitWidth = true
            $0.minimumScaleFactor = 0.85
        }
        rateLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        rateLabel.numberOfLines = 2
        rateLabel.textColor = .lightGray
        [titleLabel, translationRow, rotationRow, depthRow, geometryRow, meanLabel, qualityLabel, rateLabel].forEach(addSubview)
        showUnavailable("Waiting for a visible tag")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rows: [(UIView, CGFloat)] = [(titleLabel, 24), (translationRow, 38), (rotationRow, 34),
            (depthRow, 40), (geometryRow, 34), (meanLabel, 17), (qualityLabel, 17), (rateLabel, 34)]
        var y: CGFloat = 8
        for (view, height) in rows {
            view.frame = CGRect(x: 12, y: y, width: max(0, bounds.width - 24), height: height)
            y += height + 2
        }
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
        titleLabel.text = "TAG DEBUG · WAITING"
        titleLabel.textColor = .lightGray
        layer.borderColor = UIColor.darkGray.cgColor
        [translationRow, rotationRow, depthRow, geometryRow].forEach { $0.setValues(["—", "—", "—"]) }
        meanLabel.text = reason
        qualityLabel.text = "Point at a tag · tap its outline to select"
        rateLabel.text = "No current tag measurement"
    }
    func show(debug: [String: Any]?, frameID: String, timestamp: Double, analysisHz: Double,
              latencyMilliseconds: Double?, settings: TagDebugSettings) {
        let age = ProcessInfo.processInfo.systemUptime - timestamp
        guard age.isFinite, age <= 0.4 else { showUnavailable("Stale result · waiting for a current frame"); return }
        guard let debug else {
            showUnavailable("No tag in the current camera frame")
            rateLabel.text = String(format: "Edge %.1f mm · %.1f/30 Hz\nFrame age %.0f ms · compute %.0f ms", settings.tagSizeMeters * 1000,
                analysisHz.isFinite ? analysisHz : 0, max(0, age) * 1000, latencyMilliseconds ?? 0)
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
        titleLabel.text = "TAG #\(id) · \(titles[status] ?? status.uppercased())"
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
        rateLabel.text = String(format: "Edge %.1f mm (%@) · %.1f/30 Hz\nAge %.0f ms · compute %.0f ms", settings.tagSizeMeters * 1000,
            source, analysisHz.isFinite ? analysisHz : 0, max(0, age) * 1000, latencyMilliseconds ?? 0)
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
