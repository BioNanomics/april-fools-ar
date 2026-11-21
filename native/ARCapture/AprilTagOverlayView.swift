import UIKit

/// Image-space detections only. No world pose or physical tag size is inferred here.
final class AprilTagOverlayView: UIView {
    private var sourceFrameID: String?
    private var outlineLayers = [CAShapeLayer]()
    private var cornerLayers = [CAShapeLayer]()
    private var tagLabels = [UILabel]()
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
        hitPaths.removeAll()
    }

    func tagID(at point: CGPoint) -> Int? { hitPaths.reversed().first(where: { $0.1.contains(point) })?.0 }

    func show(_ detections: [[String: Any]], imageSize: CGSize, displayTransform: CGAffineTransform, frameID: String, expiresAt: Double, selectedID: Int? = nil) {
        let remaining = expiresAt - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, imageSize.width > 0, imageSize.height > 0 else { clear(); return }
        sourceFrameID = frameID
        var rendered = [(Int, [CGPoint], UIColor)]()
        for detection in detections {
            guard let id = detection["id"] as? NSNumber, let corners = detection["corners"] as? [[NSNumber]], corners.count == 4 else { continue }
            let points = corners.compactMap { corner -> CGPoint? in
                guard corner.count == 2 else { return nil }
                let x = corner[0].doubleValue, y = corner[1].doubleValue
                guard x.isFinite, y.isFinite else { return nil }
                let normalized = CGPoint(x: x / imageSize.width, y: y / imageSize.height).applying(displayTransform)
                guard normalized.x.isFinite, normalized.y.isFinite, bounds.width.isFinite, bounds.height.isFinite else { return nil }
                return CGPoint(x: normalized.x * bounds.width, y: normalized.y * bounds.height)
            }
            guard points.count == 4 else { continue }
            let severity = (detection["debug"] as? [String: Any])?["severity"] as? String ?? "neutral"
            let color: UIColor
            switch severity { case "good": color = .systemGreen; case "warning": color = .systemYellow; case "bad": color = .systemRed; default: color = .lightGray }
            rendered.append((id.intValue, points, color))
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
            addSubview(label); tagLabels.append(label)
        }
        hitPaths.removeAll(keepingCapacity: true)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, item) in rendered.enumerated() {
            let (id, points, color) = item
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
            label.text = id == selectedID ? " ◆ #\(id) " : " #\(id) "
            label.backgroundColor = color
            label.sizeToFit()
            label.frame.origin = CGPoint(x: max(0, min(bounds.width - label.bounds.width, points.map(\.x).min() ?? 0)), y: max(0, min(bounds.height - label.bounds.height, (points.map(\.y).min() ?? 0) - label.bounds.height)))
            hitPaths.append((id, path))
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.sourceFrameID == frameID else { return }
            self.clear()
        }
    }
}
