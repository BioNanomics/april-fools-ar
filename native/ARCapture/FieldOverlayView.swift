import UIKit
import simd

/// Predicted field geometry is deliberately separate from current image detections.
final class FieldOverlayView: UIView {
    private let outlines = CAShapeLayer(), seen = CAShapeLayer(), normals = CAShapeLayer()
    private var labels = [UILabel]()
    private var timer: Timer?
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .clear; isUserInteractionEnabled = false; clipsToBounds = true
        isAccessibilityElement = false; accessibilityIdentifier = "field.expected.overlay"
        for layer in [outlines,seen,normals] { layer.fillColor = UIColor.clear.cgColor; layer.lineWidth = 1.5; self.layer.addSublayer(layer) }
        outlines.lineDashPattern = [5,4]; outlines.strokeColor = UIColor.systemCyan.cgColor
        seen.strokeColor = UIColor.systemGreen.cgColor; normals.strokeColor = UIColor.systemPurple.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }
    func clear() { timer?.invalidate(); timer = nil; outlines.path = nil; seen.path = nil; normals.path = nil; labels.forEach { $0.isHidden = true } }
    func show(_ placements: [FieldPlacement], degraded: Bool, cameraToWorld: simd_float4x4,
              intrinsics: simd_float3x3, imageSize: CGSize, displayTransform: CGAffineTransform, expiresAt: Double) {
        guard expiresAt > ProcessInfo.processInfo.systemUptime,
              let camera = SpatialProjection.Camera(cameraToWorld: cameraToWorld, intrinsics: intrinsics, imageSize: imageSize,
                  displayTransform: displayTransform, viewportSize: bounds.size) else { clear(); return }
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: max(0.001,expiresAt-ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in self?.clear() }
        let expectedPath = UIBezierPath(), seenPath = UIBezierPath(), normalPath = UIBezierPath()
        var visible = [(FieldPlacement, CGPoint)]()
        for tag in placements.prefix(256) {
            let polygon = camera.polygon(tag.corners)
            if polygon.count >= 3 {
                let target = tag.seen ? seenPath : expectedPath
                target.move(to: polygon[0]); polygon.dropFirst().forEach { target.addLine(to: $0) }; target.close()
                if let center = camera.point(tag.center), camera.viewport.contains(center) { visible.append((tag,center)) }
            }
            if let line = camera.segment(from: tag.center, to: tag.normal) { normalPath.move(to: line[0]); normalPath.addLine(to: line[1]) }
        }
        outlines.path = expectedPath.cgPath; seen.path = seenPath.cgPath; normals.path = normalPath.cgPath
        outlines.strokeColor = (degraded ? UIColor.systemOrange : .systemCyan).cgColor
        visible = Array(visible.prefix(32))
        while labels.count < visible.count {
            let label = UILabel(); label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            label.textColor = .white; label.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            label.layer.cornerRadius = 3; label.clipsToBounds = true; label.isAccessibilityElement = true
            addSubview(label); labels.append(label)
        }
        labels.forEach { $0.isHidden = true }
        for (index, item) in visible.enumerated() {
            let (tag,point) = item, label = labels[index]
            label.isHidden = false; label.text = " Expected #\(tag.id) "
            label.accessibilityIdentifier = "field.expected.\(tag.id)"
            label.accessibilityLabel = "Expected field tag \(tag.id)"
            label.accessibilityValue = "\(tag.seen ? "Seen in this walk" : "Not seen in this walk"). \(degraded ? "Alignment needs rechecking" : "Provisional single-tag alignment")."
            label.sizeToFit(); label.frame.origin = CGPoint(x: min(max(2,point.x-label.bounds.width/2),max(2,bounds.width-label.bounds.width-2)), y: min(max(2,point.y+8),max(2,bounds.height-label.bounds.height-2)))
        }
    }
}
