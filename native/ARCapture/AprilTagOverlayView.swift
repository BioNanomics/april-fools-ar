import UIKit
import CoreFoundation

/// Image-space detections and optional camera-relative pose axes. No world pose is inferred here.
final class AprilTagOverlayView: UIView {
    struct PoseAxisProjection {
        let origin: CGPoint
        let endpoints: [CGPoint?]
    }
    private var sourceFrameID: String?
    private var outlineLayers = [CAShapeLayer]()
    private var cornerLayers = [CAShapeLayer]()
    private var tagLabels = [TagReadoutCard]()
    private var axisLayers = [CAShapeLayer]()
    private var axisLabels = [UILabel]()
    private var hitPaths = [(Int, UIBezierPath)]()
    private var cardHitPaths = [(Int, CGRect)]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func clear() {
        sourceFrameID = nil
        // UIKit owns each label's backing layer. Removing that layer directly
        // before removeFromSuperview corrupts the view/layer relationship.
        tagLabels.forEach { $0.removeFromSuperview() }
        tagLabels.removeAll()
        outlineLayers.forEach { $0.removeFromSuperlayer() }
        outlineLayers.removeAll()
        cornerLayers.forEach { $0.removeFromSuperlayer() }
        cornerLayers.removeAll()
        axisLabels.forEach { $0.removeFromSuperview() }
        axisLabels.removeAll()
        axisLayers.forEach { $0.removeFromSuperlayer() }
        axisLayers.removeAll()
        hitPaths.removeAll()
        cardHitPaths.removeAll()
    }

    func tagID(at point: CGPoint) -> Int? {
        cardHitPaths.reversed().first(where: { $0.1.contains(point) })?.0 ??
            hitPaths.reversed().first(where: { $0.1.contains(point) })?.0
    }

    /// Intrinsics are [fx, fy, cx, cy] in the analyzed source image's pixels.
    /// Pose R maps tag coordinates to optical camera coordinates (+X right, +Y down, +Z forward).
    /// The default axis length is half the calibrated tag width; no 2D-only pose is synthesized.
    func show(_ detections: [[String: Any]], imageSize: CGSize, displayTransform: CGAffineTransform, frameID: String, expiresAt: Double, selectedID: Int? = nil, showPoseAxes: Bool = false, intrinsics: [Double]? = nil, axisLengthMeters: Double? = nil, showImperialHeight: Bool = true, distanceDeltaThresholdMeters: Double = 0.15) {
        let remaining = expiresAt - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { clear(); return }
        sourceFrameID = frameID
        var rendered = [(Int, [CGPoint], UIColor, [String: Any]?, [String: Any]?)]()
        var renderedAxes = [PoseAxisProjection]()
        func displayPoint(_ point: CGPoint) -> CGPoint? {
            let normalized = CGPoint(x: point.x / imageSize.width, y: point.y / imageSize.height).applying(displayTransform)
            let mapped = CGPoint(x: normalized.x * bounds.width, y: normalized.y * bounds.height)
            return mapped.x.isFinite && mapped.y.isFinite ? mapped : nil
        }
        for detection in detections {
            guard let id = detection["id"] as? NSNumber, let corners = detection["corners"] as? [[NSNumber]], corners.count == 4 else { continue }
            let points = corners.compactMap { corner -> CGPoint? in
                guard corner.count == 2 else { return nil }
                let x = corner[0].doubleValue, y = corner[1].doubleValue
                guard x.isFinite, y.isFinite else { return nil }
                return displayPoint(CGPoint(x: x, y: y))
            }
            guard points.count == 4 else { continue }
            guard Self.enclosingRect(points).intersects(bounds) else { continue }
            let severity = (detection["debug"] as? [String: Any])?["severity"] as? String ?? "neutral"
            let color: UIColor
            switch severity { case "good": color = .systemGreen; case "warning": color = .systemYellow; case "bad": color = .systemRed; default: color = .lightGray }
            // Keep metadata beside its own detection: duplicate tag IDs may be at different heights.
            let floorHeight = detection["floorHeight"].map { $0 as? [String: Any] ?? [:] }
            let cameraRanges = detection["cameraRanges"] as? [String: Any]
            rendered.append((id.intValue, points, color, floorHeight, cameraRanges))
            if showPoseAxes, let intrinsics, let pose = detection["pose"] as? [String: Any],
               let projected = Self.projectPoseAxes(pose: pose, intrinsics: intrinsics, axisLengthMeters: axisLengthMeters),
               let origin = displayPoint(projected.origin) {
                renderedAxes.append(PoseAxisProjection(origin: origin, endpoints: projected.endpoints.map { $0.flatMap(displayPoint) }))
            }
        }
        // Reuse only layers/views owned by this overlay. UIKit owns label backing layers.
        while tagLabels.count > rendered.count {
            tagLabels.removeLast().removeFromSuperview()
            outlineLayers.removeLast().removeFromSuperlayer()
            cornerLayers.removeLast().removeFromSuperlayer()
        }
        while tagLabels.count < rendered.count {
            let shape = CAShapeLayer(), corners = CAShapeLayer(), label = TagReadoutCard()
            shape.lineJoin = .round
            corners.lineWidth = 1; corners.strokeColor = UIColor.black.cgColor
            layer.addSublayer(shape); layer.addSublayer(corners)
            outlineLayers.append(shape); cornerLayers.append(corners)
            label.layer.cornerRadius = 5; label.clipsToBounds = true
            label.backgroundColor = UIColor.black.withAlphaComponent(0.76)
            label.isAccessibilityElement = true
            addSubview(label); tagLabels.append(label)
        }
        let axisColors: [UIColor] = [.systemRed, .systemGreen, .systemBlue]
        while axisLabels.count > renderedAxes.count * 3 {
            axisLabels.removeLast().removeFromSuperview()
            axisLayers.removeLast().removeFromSuperlayer()
        }
        while axisLabels.count < renderedAxes.count * 3 {
            let axis = axisLabels.count % 3, shape = CAShapeLayer(), label = UILabel()
            shape.strokeColor = axisColors[axis].cgColor; shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 2.5; shape.lineCap = .round; shape.lineJoin = .round
            shape.shadowColor = UIColor.black.cgColor; shape.shadowOpacity = 0.9; shape.shadowRadius = 1; shape.shadowOffset = .zero
            layer.addSublayer(shape); axisLayers.append(shape)
            label.text = [" X ", " Y ", " Z "][axis]
            label.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
            label.textColor = axisColors[axis]; label.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            label.layer.cornerRadius = 3; label.clipsToBounds = true
            addSubview(label); axisLabels.append(label)
        }
        hitPaths.removeAll(keepingCapacity: true)
        cardHitPaths.removeAll(keepingCapacity: true)
        let tagRects = rendered.map { Self.enclosingRect($0.1) }
        var placedCards = [CGRect]()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, item) in rendered.enumerated() {
            let (id, points, color, floorHeight, cameraRanges) = item
            let path = UIBezierPath()
            path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            let shape = outlineLayers[index]
            shape.path = path.cgPath
            shape.strokeColor = color.cgColor
            shape.fillColor = color.withAlphaComponent(0.06).cgColor
            shape.lineWidth = id == selectedID ? 3.5 : 2
            let dots = UIBezierPath()
            for point in points { dots.append(UIBezierPath(ovalIn: CGRect(x: point.x-4, y: point.y-4, width: 8, height: 8))) }
            cornerLayers[index].path = dots.cgPath; cornerLayers[index].fillColor = color.cgColor
            let label = tagLabels[index]
            configure(label, id: id, selected: id == selectedID, floorHeight: floorHeight, cameraRanges: cameraRanges, showImperialHeight: showImperialHeight, distanceDeltaThresholdMeters: distanceDeltaThresholdMeters)
            label.setTextColor(color)
            label.layer.borderColor = color.withAlphaComponent(0.85).cgColor
            label.layer.borderWidth = id == selectedID ? 1.5 : 0.75
            let cardSize = label.preferredSize(maximumWidth: max(0, bounds.width - 12), maximumHeight: bounds.height)
            label.frame = placeCard(size: cardSize, around: tagRects[index], occupied: placedCards, tags: tagRects)
            label.setNeedsLayout(); label.layoutIfNeeded()
            placedCards.append(label.frame)
            let start = Self.nearestPoint(in: tagRects[index], to: CGPoint(x: label.frame.midX, y: label.frame.midY))
            let end = Self.nearestPoint(in: label.frame, to: CGPoint(x: tagRects[index].midX, y: tagRects[index].midY))
            if hypot(start.x - end.x, start.y - end.y) > 7 {
                // The leader belongs to the existing outline layer, never a UIKit label's backing layer.
                let outlineWithLeader = UIBezierPath(cgPath: path.cgPath)
                outlineWithLeader.move(to: start); outlineWithLeader.addLine(to: end)
                shape.path = outlineWithLeader.cgPath
            }
            hitPaths.append((id, path))
            cardHitPaths.append((id, label.frame))
        }
        for (tagIndex, projection) in renderedAxes.enumerated() {
            let origin = projection.origin
            for axis in 0..<3 {
                let index = tagIndex * 3 + axis
                guard let end = projection.endpoints[axis] else {
                    axisLayers[index].isHidden = true; axisLabels[index].isHidden = true
                    continue
                }
                axisLayers[index].isHidden = false; axisLabels[index].isHidden = false
                let path = UIBezierPath()
                path.move(to: origin); path.addLine(to: end)
                let dx = end.x - origin.x, dy = end.y - origin.y, length = hypot(dx, dy)
                if length > 1 {
                    let ux = dx / length, uy = dy / length, head = min(8, length * 0.3)
                    path.move(to: CGPoint(x: end.x - ux * head - uy * head * 0.5, y: end.y - uy * head + ux * head * 0.5))
                    path.addLine(to: end)
                    path.addLine(to: CGPoint(x: end.x - ux * head + uy * head * 0.5, y: end.y - uy * head - ux * head * 0.5))
                } else {
                    // A head-on Z axis can project to a point. Keep it visible without inventing direction.
                    path.append(UIBezierPath(ovalIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)))
                }
                axisLayers[index].path = path.cgPath
                let label = axisLabels[index]
                label.sizeToFit()
                label.frame.origin = CGPoint(x: max(0, min(bounds.width - label.bounds.width, end.x + 5)),
                                             y: max(0, min(bounds.height - label.bounds.height, end.y - label.bounds.height - 3)))
            }
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.sourceFrameID == frameID else { return }
            self.clear()
        }
    }

    private func configure(_ label: TagReadoutCard, id: Int, selected: Bool, floorHeight: [String: Any]?, cameraRanges: [String: Any]?, showImperialHeight: Bool, distanceDeltaThresholdMeters: Double) {
        let prefix = selected ? "◆ #\(id)" : "#\(id)"
        label.accessibilityIdentifier = "apriltag.label.\(id)"
        label.accessibilityLabel = "AprilTag \(id)"
        label.accessibilityTraits = selected ? [.staticText, .selected] : .staticText
        let floorHeight = floorHeight ?? [:]
        let source = floorHeight["source"] as? String ?? "unavailable"
        let sourceName = source == "sceneDepth" ? "LiDAR depth" : (source == "tagPose" ? "optical tag pose" : "unavailable or unrecognized")
        let reason = floorHeight["reason"] as? String ?? "No current floor-height estimate"
        func isTrue(_ value: Any?) -> Bool {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            return number.boolValue
        }
        let suppliedAvailable = isTrue(floorHeight["available"])
        let raw = floorHeight["meters"] as? NSNumber
        let meters = raw?.doubleValue ?? .nan
        let valid = suppliedAvailable && raw.map { CFGetTypeID($0) != CFBooleanGetTypeID() } == true &&
            meters.isFinite && (0...30).contains(meters) && ["sceneDepth", "tagPose"].contains(source)
        let heightText: String, heightAccessibility: String
        if valid, let formatted = HeightDisplayFormatter.string(meters: meters, showImperial: showImperialHeight) {
            heightText = formatted
            heightAccessibility = "Floor-relative tag center height available: \(formatted). Source: \(sourceName). Reason: \(reason)."
        } else {
            heightText = "—"
            let explanation = suppliedAvailable ? "Invalid floor-height estimate" : (reason == "floorNotSelected" ? "Floor not selected; set a floor" : reason)
            heightAccessibility = "Floor-relative tag center height unavailable. Source: \(sourceName). Reason: \(explanation)."
        }
        let ranges = cameraRanges ?? [:]
        func range(_ key: String, available: String, reason: String, name: String) -> (String, Double?, String) {
            let value = ranges[key] as? NSNumber
            let meters = value?.doubleValue ?? .nan
            if isTrue(ranges[available]), let value, CFGetTypeID(value) != CFBooleanGetTypeID(),
               meters.isFinite, meters > 0, let formatted = HeightDisplayFormatter.string(meters: meters, showImperial: showImperialHeight) {
                return (formatted, meters, "\(name) camera range available: \(formatted).")
            }
            return ("—", nil, "\(name) camera range unavailable. Reason: \(ranges[reason] as? String ?? "No current range estimate").")
        }
        let lidar = range("lidarRangeMeters", available: "lidarAvailable", reason: "lidarReason", name: "LiDAR")
        let tag = range("tagRangeMeters", available: "tagAvailable", reason: "tagReason", name: "Tag pose")
        var deltaText: String?
        if let lidarMeters = lidar.1, let tagMeters = tag.1, distanceDeltaThresholdMeters.isFinite,
           distanceDeltaThresholdMeters >= 0 {
            let computed = abs(lidarMeters - tagMeters)
            let supplied = ranges["distanceDeltaMeters"] as? NSNumber
            let delta = supplied.flatMap { number -> Double? in
                let value = number.doubleValue
                guard CFGetTypeID(number) != CFBooleanGetTypeID(), value.isFinite, value >= 0,
                      abs(value - computed) <= 1e-9 * max(1, computed) else { return nil }
                return value
            } ?? computed
            if delta > distanceDeltaThresholdMeters {
                deltaText = HeightDisplayFormatter.string(meters: delta, showImperial: showImperialHeight)
            }
        }
        let filtered = floorHeight["readoutFilter"] != nil || ranges["readoutFilter"] != nil
        label.setContent(id: id, summary: "\(prefix) · H \(heightText)", lidar: lidar.0, tag: tag.0,
                         delta: deltaText, showImperial: showImperialHeight, filtered: filtered)
        label.accessibilityValue = heightAccessibility + " Distance. " + lidar.2 + " " + tag.2
        if filtered {
            label.accessibilityValue = (label.accessibilityValue ?? "") + " Kalman smoothing applied to live readouts."
        }
        if let deltaText {
            label.accessibilityValue = (label.accessibilityValue ?? "") + " Absolute LiDAR versus Tag camera range difference: \(deltaText)."
        }
    }

    private static func enclosingRect(_ points: [CGPoint]) -> CGRect {
        let x = points.map(\.x), y = points.map(\.y)
        return CGRect(x: x.min() ?? 0, y: y.min() ?? 0, width: (x.max() ?? 0) - (x.min() ?? 0), height: (y.max() ?? 0) - (y.min() ?? 0))
    }

    private static func nearestPoint(in rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(x: max(rect.minX, min(rect.maxX, point.x)), y: max(rect.minY, min(rect.maxY, point.y)))
    }

    private func placeCard(size: CGSize, around tag: CGRect, occupied: [CGRect], tags: [CGRect]) -> CGRect {
        let gap: CGFloat = 6
        let horizontalMargin = min(gap, max(0, (bounds.width - size.width) / 2))
        let normalHeight = bounds.height >= size.height + 160
        let desiredTop: CGFloat = normalHeight ? 88 : gap
        let desiredBottom: CGFloat = normalHeight ? 64 : gap
        let reserveScale = min(CGFloat(1), max(0, bounds.height - size.height) / (desiredTop + desiredBottom))
        let top = desiredTop * reserveScale, bottom = desiredBottom * reserveScale
        let area = CGRect(x: horizontalMargin, y: top, width: max(0, bounds.width - horizontalMargin * 2), height: max(0, bounds.height - top - bottom))
        func clamped(_ point: CGPoint) -> CGRect {
            CGRect(x: max(area.minX, min(area.maxX - size.width, point.x)),
                   y: max(area.minY, min(area.maxY - size.height, point.y)), width: size.width, height: size.height)
        }
        var origins = [CGPoint(x: tag.minX, y: tag.minY - size.height - gap),
                       CGPoint(x: tag.minX, y: tag.maxY + gap),
                       CGPoint(x: tag.minX - size.width - gap, y: tag.midY - size.height / 2),
                       CGPoint(x: tag.maxX + gap, y: tag.midY - size.height / 2)]
        // Bounded vertical fallback slots make nearby tags legible when their four immediate sides collide.
        let slots = min(24, max(1, Int(area.height / max(size.height + gap, 1))))
        for slot in 0..<slots {
            let y = area.minY + CGFloat(slot) * (size.height + gap)
            origins.append(CGPoint(x: area.minX, y: y))
            origins.append(CGPoint(x: area.maxX - size.width, y: y))
        }
        func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let intersection = a.intersection(b)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        func score(_ rect: CGRect) -> CGFloat {
            let cardOverlap = occupied.reduce(CGFloat.zero) { $0 + overlap(rect.insetBy(dx: -3, dy: -3), $1) }
            let tagOverlap = tags.reduce(CGFloat.zero) { $0 + overlap(rect, $1) }
            let distance = hypot(rect.midX - tag.midX, rect.midY - tag.midY)
            return cardOverlap * 100 + tagOverlap * 3 + distance * 0.1
        }
        return origins.map(clamped).enumerated().min {
            let a = score($0.element), b = score($1.element)
            return abs(a - b) < 1e-6 ? $0.offset < $1.offset : a < b
        }!.element
    }

    /// Pure pinhole projection in original image pixels; endpoints are ordered [+X, +Y, +Z].
    /// A behind-camera endpoint suppresses only its axis. A bad origin suppresses the entire gizmo.
    static func projectPoseAxes(pose: [String: Any], intrinsics: [Double], axisLengthMeters: Double? = nil) -> PoseAxisProjection? {
        guard intrinsics.count == 4, intrinsics.allSatisfy(\.isFinite), intrinsics[0] > 0, intrinsics[1] > 0,
              let rotation = pose["rotationRowMajor"] as? [NSNumber], rotation.count == 9,
              let translation = pose["translation"] as? [NSNumber], translation.count == 3 else { return nil }
        let r = rotation.map(\.doubleValue), t = translation.map(\.doubleValue)
        let length = axisLengthMeters ?? (pose["tagSizeMeters"] as? NSNumber).map { $0.doubleValue / 2 } ?? .nan
        guard r.allSatisfy(\.isFinite), t.allSatisfy(\.isFinite), length.isFinite, length > 0 else { return nil }
        // A malformed matrix must not produce a plausible-looking gizmo.
        for a in 0..<3 { for b in 0..<3 {
            let dot = r[a] * r[b] + r[3 + a] * r[3 + b] + r[6 + a] * r[6 + b]
            guard abs(dot - (a == b ? 1 : 0)) < 1e-3 else { return nil }
        } }
        let determinant = r[0] * (r[4] * r[8] - r[5] * r[7]) - r[1] * (r[3] * r[8] - r[5] * r[6]) + r[2] * (r[3] * r[7] - r[4] * r[6])
        guard abs(determinant - 1) < 1e-3 else { return nil }
        func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint? {
            guard x.isFinite, y.isFinite, z.isFinite, z > 1e-6 else { return nil }
            let pixel = CGPoint(x: intrinsics[0] * x / z + intrinsics[2], y: intrinsics[1] * y / z + intrinsics[3])
            guard pixel.x.isFinite, pixel.y.isFinite else { return nil }
            return pixel
        }
        guard let origin = project(t[0], t[1], t[2]) else { return nil }
        let endpoints = (0..<3).map { axis in project(t[0] + length * r[axis], t[1] + length * r[3 + axis], t[2] + length * r[6 + axis]) }
        return PoseAxisProjection(origin: origin, endpoints: endpoints)
    }
}

/// One reusable card per detection. Metric values share a right-aligned column;
/// optional English units have their own column, so their varying lengths never move the cm decimals.
private final class TagReadoutCard: UIView {
    private let summaryLabel = UILabel()
    private let headingLabel = UILabel()
    private let sourceLabels = (0..<3).map { _ in UILabel() }
    private let metricLabels = (0..<3).map { _ in UILabel() }
    private let englishLabels = (0..<3).map { _ in UILabel() }
    private var hasDelta = false
    private var hasEnglish = false
    private let rowHeight: CGFloat = 15

    override init(frame: CGRect) {
        super.init(frame: frame)
        let labels = [summaryLabel, headingLabel] + sourceLabels + metricLabels + englishLabels
        for label in labels {
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.9
            label.isAccessibilityElement = false
            addSubview(label)
        }
        headingLabel.text = "Distance"
        for label in metricLabels { label.textAlignment = .right }
        sourceLabels[0].text = "LiDAR"; sourceLabels[1].text = "Tag"; sourceLabels[2].text = "LiDAR Δ"
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContent(id: Int, summary: String, lidar: String, tag: String, delta: String?, showImperial: Bool, filtered: Bool) {
        summaryLabel.text = summary
        headingLabel.text = filtered ? "Distance · Kalman" : "Distance"
        summaryLabel.accessibilityIdentifier = "apriltag.summary.\(id)"
        headingLabel.accessibilityIdentifier = "apriltag.distanceHeading.\(id)"
        let names = ["lidar", "tag", "delta"]
        let values = [lidar, tag, delta ?? "—"]
        hasDelta = delta != nil
        hasEnglish = false
        for index in 0..<3 {
            let parts = values[index].components(separatedBy: " (")
            metricLabels[index].text = parts.first ?? "—"
            let english = showImperial && parts.count == 2 ? "(" + parts[1] : ""
            englishLabels[index].text = english
            let visible = index < 2 || hasDelta
            sourceLabels[index].isHidden = !visible
            metricLabels[index].isHidden = !visible
            englishLabels[index].isHidden = !visible || english.isEmpty
            hasEnglish = hasEnglish || (visible && !english.isEmpty)
            sourceLabels[index].accessibilityIdentifier = "apriltag.\(names[index])Title.\(id)"
            metricLabels[index].accessibilityIdentifier = "apriltag.\(names[index])Metric.\(id)"
            englishLabels[index].accessibilityIdentifier = "apriltag.\(names[index])English.\(id)"
        }
        setNeedsLayout()
    }

    func setTextColor(_ color: UIColor) {
        ([summaryLabel, headingLabel] + sourceLabels + metricLabels + englishLabels).forEach { $0.textColor = color }
        if hasDelta {
            [sourceLabels[2], metricLabels[2], englishLabels[2]].forEach { $0.textColor = .systemOrange }
        }
    }

    func preferredSize(maximumWidth: CGFloat, maximumHeight: CGFloat) -> CGSize {
        let width = hasEnglish ? 260 : max(150, min(260, summaryLabel.intrinsicContentSize.width + 12))
        return CGSize(width: min(width, maximumWidth), height: min(rowHeight * (hasDelta ? 5 : 4) + 8, maximumHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padding = min(CGFloat(6), bounds.width / 2)
        let inner = max(0, bounds.width - padding * 2)
        func frame(x: CGFloat, y: CGFloat, width: CGFloat) -> CGRect {
            let top = min(bounds.height, y)
            return CGRect(x: x, y: top, width: max(0, width), height: max(0, min(rowHeight, bounds.height - top)))
        }
        summaryLabel.frame = frame(x: padding, y: 4, width: inner)
        headingLabel.frame = frame(x: padding, y: 4 + rowHeight, width: inner)
        let sourceWidth = min(CGFloat(54), inner * 0.24)
        let gap = min(CGFloat(4), max(0, inner - sourceWidth) / 2)
        let metricX = padding + sourceWidth + gap
        let metricWidth = hasEnglish ? min(CGFloat(72), max(0, inner - sourceWidth - gap)) : max(0, inner - sourceWidth - gap)
        let englishX = min(bounds.width - padding, metricX + metricWidth + gap)
        let englishWidth = max(0, bounds.width - padding - englishX)
        for index in 0..<3 {
            let y = 4 + rowHeight * CGFloat(index + 2)
            sourceLabels[index].frame = frame(x: padding, y: y, width: sourceWidth)
            metricLabels[index].frame = frame(x: metricX, y: y, width: metricWidth)
            englishLabels[index].frame = frame(x: englishX, y: y, width: englishWidth)
        }
    }
}
