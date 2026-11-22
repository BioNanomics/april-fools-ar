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
    private var tagLabels = [UILabel]()
    private var axisLayers = [CAShapeLayer]()
    private var axisLabels = [UILabel]()
    private var hitPaths = [(Int, UIBezierPath)]()

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
    }

    func tagID(at point: CGPoint) -> Int? { hitPaths.reversed().first(where: { $0.1.contains(point) })?.0 }

    /// Intrinsics are [fx, fy, cx, cy] in the analyzed source image's pixels.
    /// Pose R maps tag coordinates to optical camera coordinates (+X right, +Y down, +Z forward).
    /// The default axis length is half the calibrated tag width; no 2D-only pose is synthesized.
    func show(_ detections: [[String: Any]], imageSize: CGSize, displayTransform: CGAffineTransform, frameID: String, expiresAt: Double, selectedID: Int? = nil, showPoseAxes: Bool = false, intrinsics: [Double]? = nil, axisLengthMeters: Double? = nil, showImperialHeight: Bool = true) {
        let remaining = expiresAt - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0, bounds.width.isFinite, bounds.height.isFinite else { clear(); return }
        sourceFrameID = frameID
        var rendered = [(Int, [CGPoint], UIColor, [String: Any]?)]()
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
            let severity = (detection["debug"] as? [String: Any])?["severity"] as? String ?? "neutral"
            let color: UIColor
            switch severity { case "good": color = .systemGreen; case "warning": color = .systemYellow; case "bad": color = .systemRed; default: color = .lightGray }
            // Keep metadata beside its own detection: duplicate tag IDs may be at different heights.
            let floorHeight = detection["floorHeight"].map { $0 as? [String: Any] ?? [:] }
            rendered.append((id.intValue, points, color, floorHeight))
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
            let shape = CAShapeLayer(), corners = CAShapeLayer(), label = UILabel()
            shape.lineJoin = .round
            corners.lineWidth = 1; corners.strokeColor = UIColor.black.cgColor
            layer.addSublayer(shape); layer.addSublayer(corners)
            outlineLayers.append(shape); cornerLayers.append(corners)
            label.font = .monospacedSystemFont(ofSize: 17, weight: .bold)
            label.textColor = .black; label.layer.cornerRadius = 4; label.clipsToBounds = true
            label.numberOfLines = 1; label.lineBreakMode = .byTruncatingTail
            label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.75
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
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, item) in rendered.enumerated() {
            let (id, points, color, floorHeight) = item
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
            configure(label, id: id, selected: id == selectedID, floorHeight: floorHeight, showImperialHeight: showImperialHeight)
            label.backgroundColor = color
            label.sizeToFit()
            label.bounds.size = CGSize(width: min(label.bounds.width, max(0, bounds.width)), height: min(label.bounds.height, max(0, bounds.height)))
            label.frame.origin = CGPoint(x: max(0, min(bounds.width - label.bounds.width, points.map(\.x).min() ?? 0)), y: max(0, min(bounds.height - label.bounds.height, (points.map(\.y).min() ?? 0) - label.bounds.height)))
            hitPaths.append((id, path))
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

    private func configure(_ label: UILabel, id: Int, selected: Bool, floorHeight: [String: Any]?, showImperialHeight: Bool) {
        let prefix = selected ? " ◆ #\(id)" : " #\(id)"
        label.accessibilityIdentifier = "apriltag.label.\(id)"
        label.accessibilityLabel = "AprilTag \(id)"
        label.accessibilityTraits = selected ? [.staticText, .selected] : .staticText
        guard let floorHeight else {
            // Old detection-only inputs keep their exact display text and do not imply floor data exists.
            label.font = .monospacedSystemFont(ofSize: 17, weight: .bold)
            label.text = prefix + " "
            label.accessibilityValue = "Floor-relative height not provided"
            return
        }
        label.font = .monospacedSystemFont(ofSize: 17, weight: .bold)
        let source = floorHeight["source"] as? String ?? "unavailable"
        let sourceName = source == "sceneDepth" ? "LiDAR depth" : (source == "tagPose" ? "optical tag pose" : "unavailable or unrecognized")
        let reason = floorHeight["reason"] as? String ?? "No current floor-height estimate"
        let suppliedAvailable = floorHeight["available"] as? Bool == true
        let raw = floorHeight["meters"] as? NSNumber
        let meters = raw?.doubleValue ?? .nan
        let valid = suppliedAvailable && raw.map { CFGetTypeID($0) != CFBooleanGetTypeID() } == true &&
            meters.isFinite && (0...30).contains(meters) && ["sceneDepth", "tagPose"].contains(source)
        if valid, let formatted = HeightDisplayFormatter.string(meters: meters, showImperial: showImperialHeight) {
            label.text = prefix + " · ↑ \(formatted) "
            label.accessibilityValue = "Floor-relative tag center height available: \(formatted). Source: \(sourceName). Reason: \(reason)."
        } else {
            label.text = prefix + " · H — "
            let explanation = suppliedAvailable ? "Invalid floor-height estimate" : (reason == "floorNotSelected" ? "Floor not selected; set a floor" : reason)
            label.accessibilityValue = "Floor-relative tag center height unavailable. Source: \(sourceName). Reason: \(explanation)."
        }
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
