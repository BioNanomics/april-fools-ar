import UIKit

/// Image-space detections only. No world pose or physical tag size is inferred here.
final class AprilTagOverlayView: UIView {
    private var sourceFrameID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func clear() {
        sourceFrameID = nil
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        subviews.forEach { $0.removeFromSuperview() }
    }

    func show(_ detections: [[String: Any]], imageSize: CGSize, displayTransform: CGAffineTransform, frameID: String, expiresAt: Double) {
        clear()
        let remaining = expiresAt - ProcessInfo.processInfo.systemUptime
        guard remaining > 0, imageSize.width > 0, imageSize.height > 0 else { return }
        sourceFrameID = frameID
        for detection in detections {
            guard let id = detection["id"] as? NSNumber, let corners = detection["corners"] as? [[NSNumber]], corners.count == 4 else { continue }
            let points = corners.compactMap { corner -> CGPoint? in
                guard corner.count == 2 else { return nil }
                let x = corner[0].doubleValue, y = corner[1].doubleValue
                guard x.isFinite, y.isFinite else { return nil }
                let normalized = CGPoint(x: x / imageSize.width, y: y / imageSize.height).applying(displayTransform)
                return CGPoint(x: normalized.x * bounds.width, y: normalized.y * bounds.height)
            }
            guard points.count == 4 else { continue }
            let path = UIBezierPath()
            path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            let shape = CAShapeLayer()
            shape.path = path.cgPath
            shape.strokeColor = UIColor.systemGreen.cgColor
            shape.fillColor = UIColor.systemGreen.withAlphaComponent(0.09).cgColor
            shape.lineWidth = 2.5
            shape.lineJoin = .round
            layer.addSublayer(shape)
            let label = UILabel()
            label.text = " #\(id.intValue) "
            label.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
            label.textColor = .black
            label.backgroundColor = .systemGreen
            label.layer.cornerRadius = 4; label.clipsToBounds = true
            label.sizeToFit()
            label.frame.origin = CGPoint(x: max(0, min(bounds.width - label.bounds.width, points.map(\.x).min() ?? 0)), y: max(0, min(bounds.height - label.bounds.height, (points.map(\.y).min() ?? 0) - label.bounds.height)))
            addSubview(label)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.sourceFrameID == frameID else { return }
            self.clear()
        }
    }
}
