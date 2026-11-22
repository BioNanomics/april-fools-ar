import UIKit
import simd

/// Passive screen projection of immutable world placements. The caller owns tracking/segment lifetime.
final class SpatialMeasurementOverlayView: UIView {
    private final class PlaneSlot {
        let shape = CAShapeLayer()
        let label = UILabel()
        init(in view: UIView) {
            shape.lineWidth = 1.5; shape.lineJoin = .round
            view.layer.addSublayer(shape)
            SpatialMeasurementOverlayView.style(label)
            view.addSubview(label)
        }
        func remove() { label.removeFromSuperview(); shape.removeFromSuperlayer() }
    }
    private final class VectorSlot {
        let line = CAShapeLayer(), dots = CAShapeLayer()
        let label = UILabel()
        init(in view: UIView) {
            line.lineWidth = 2.5; line.lineCap = .round; line.lineJoin = .round
            line.fillColor = UIColor.clear.cgColor
            line.shadowColor = UIColor.black.cgColor; line.shadowOpacity = 0.8; line.shadowRadius = 1; line.shadowOffset = .zero
            dots.lineWidth = 1.5; dots.strokeColor = UIColor.black.cgColor
            view.layer.addSublayer(line); view.layer.addSublayer(dots)
            SpatialMeasurementOverlayView.style(label)
            view.addSubview(label)
        }
        func remove() { label.removeFromSuperview(); line.removeFromSuperlayer(); dots.removeFromSuperlayer() }
    }
    private var planeSlots = [PlaneSlot]()
    private var vectorSlots = [VectorSlot]()
    private var pendingSlots = [VectorSlot]()
    private var floorHitPaths = [(String, UIBezierPath)]()
    private var expiryDeadline: Double?
    private var expiryTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isUserInteractionEnabled = false; clipsToBounds = true
        isAccessibilityElement = false
        accessibilityIdentifier = "spatial.measurement.overlay"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { expiryTimer?.invalidate() }

    private static func style(_ label: UILabel) {
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white; label.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        label.layer.cornerRadius = 4; label.clipsToBounds = true
        label.isAccessibilityElement = true; label.accessibilityTraits = .staticText
    }

    func clear() {
        expiryTimer?.invalidate(); expiryTimer = nil; expiryDeadline = nil
        planeSlots.forEach { $0.remove() }; planeSlots.removeAll()
        vectorSlots.forEach { $0.remove() }; vectorSlots.removeAll()
        pendingSlots.forEach { $0.remove() }; pendingSlots.removeAll()
        floorHitPaths.removeAll()
    }

    func floorPlaneID(at point: CGPoint) -> String? { floorHitPaths.reversed().first(where: { $0.1.contains(point) })?.0 }
    func floorID(at point: CGPoint) -> String? { floorPlaneID(at: point) }

    /// displayTransform already includes display magnification exactly once, like the tag renderer.
    func show(planes: [SpatialPlane], measurements: [SpatialMeasurement], pendingPoints: [SIMD3<Float>],
              selectedFloorID: String?, isTrackingNormal: Bool, cameraToWorld: simd_float4x4,
              intrinsics: simd_float3x3, imageSize: CGSize, displayTransform: CGAffineTransform, expiresAt: Double? = nil) {
        let deadline = expiresAt ?? (ProcessInfo.processInfo.systemUptime + 0.5)
        guard deadline.isFinite, deadline > ProcessInfo.processInfo.systemUptime,
              isTrackingNormal, let camera = SpatialProjection.Camera(cameraToWorld: cameraToWorld,
              intrinsics: intrinsics, imageSize: imageSize, displayTransform: displayTransform, viewportSize: bounds.size) else { clear(); return }
        armExpiry(at: deadline)
        var planeGeometry = [(SpatialPlane, [CGPoint])]()
        // Prioritize the operator-confirmed plane when the candidate budget is full.
        let candidates = planes.sorted { ($0.id == selectedFloorID ? 0 : 1) < ($1.id == selectedFloorID ? 0 : 1) }.prefix(24)
        for plane in candidates {
            let polygon = camera.polygon(plane.vertices)
            guard polygon.count >= 3 else { continue }
            var doubleArea: CGFloat = 0
            for index in polygon.indices {
                let a = polygon[index], b = polygon[(index + 1) % polygon.count]
                doubleArea += a.x * b.y - b.x * a.y
            }
            if abs(doubleArea) > 2 { planeGeometry.append((plane, polygon)) }
        }
        var vectors = [(SpatialMeasurement, [CGPoint])]()
        for measurement in measurements.suffix(50) {
            guard measurement.distanceMeters.isFinite, measurement.verticalMeters.isFinite,
                  let segment = camera.segment(from: measurement.start, to: measurement.end) else { continue }
            vectors.append((measurement, segment))
        }
        let pending = pendingPoints.prefix(2).enumerated().compactMap { index, world -> (Int, CGPoint)? in
            guard let point = camera.point(world), camera.viewport.contains(point) else { return nil }
            return (index, point)
        }
        while planeSlots.count > planeGeometry.count { planeSlots.removeLast().remove() }
        while planeSlots.count < planeGeometry.count { planeSlots.append(PlaneSlot(in: self)) }
        while vectorSlots.count > vectors.count { vectorSlots.removeLast().remove() }
        while vectorSlots.count < vectors.count { vectorSlots.append(VectorSlot(in: self)) }
        while pendingSlots.count > pending.count { pendingSlots.removeLast().remove() }
        while pendingSlots.count < pending.count { pendingSlots.append(VectorSlot(in: self)) }

        floorHitPaths.removeAll(keepingCapacity: true)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, geometry) in planeGeometry.enumerated() {
            let (plane, polygon) = geometry, slot = planeSlots[index]
            let selected = plane.id == selectedFloorID
            let confirmed = selected || plane.classification.lowercased() == "floor"
            let title = confirmed ? "Floor" : "Horizontal surface"
            let color: UIColor = selected ? .systemCyan : (confirmed ? .systemTeal : .systemMint)
            let path = UIBezierPath(); path.move(to: polygon[0])
            polygon.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            slot.shape.path = path.cgPath; slot.shape.strokeColor = color.withAlphaComponent(0.8).cgColor
            slot.shape.fillColor = color.withAlphaComponent(selected ? 0.15 : 0.06).cgColor
            slot.shape.lineDashPattern = confirmed ? nil : [5, 4]
            slot.label.text = selected ? " Floor · selected " : " \(title) "
            slot.label.textColor = color
            slot.label.accessibilityIdentifier = "spatial.plane.\(plane.id)"
            slot.label.accessibilityLabel = selected ? "Selected floor plane" : (confirmed ? "Detected floor plane" : "Horizontal surface candidate")
            slot.label.accessibilityValue = "ID \(plane.id)"
            let center = polygon.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            place(slot.label, near: CGPoint(x: center.x / CGFloat(polygon.count), y: center.y / CGFloat(polygon.count)))
            floorHitPaths.append((plane.id, path))
        }
        for (index, geometry) in vectors.enumerated() {
            let (measurement, segment) = geometry, slot = vectorSlots[index]
            let isHeight = measurement.kind == "height", color: UIColor = isHeight ? .systemOrange : .systemYellow
            slot.line.path = arrow(from: segment[0], to: segment[1]).cgPath
            slot.line.strokeColor = color.cgColor; slot.dots.fillColor = color.cgColor
            let dots = UIBezierPath()
            for world in [measurement.start, measurement.end] {
                if let point = camera.point(world), camera.viewport.contains(point) {
                    dots.append(UIBezierPath(ovalIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)))
                }
            }
            slot.dots.path = dots.cgPath
            let distance = Double(measurement.distanceMeters), vertical = Double(measurement.verticalMeters)
            slot.label.text = isHeight ? String(format: " Height %.3f m ", abs(vertical)) : String(format: " %.3f m · ΔY %.3f m ", distance, vertical)
            slot.label.textColor = color
            slot.label.accessibilityIdentifier = "spatial.measurement.\(measurement.id)"
            slot.label.accessibilityLabel = isHeight ? "Height measurement" : "Distance measurement"
            slot.label.accessibilityValue = String(format: "ID %@. Distance %.3f meters. Vertical difference %.3f meters.", measurement.id, distance, vertical)
            place(slot.label, near: CGPoint(x: (segment[0].x + segment[1].x) / 2, y: (segment[0].y + segment[1].y) / 2 - 14))
        }
        for (slotIndex, pointData) in pending.enumerated() {
            let (pointIndex, point) = pointData, slot = pendingSlots[slotIndex]
            let marker = UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
            marker.move(to: CGPoint(x: point.x - 11, y: point.y)); marker.addLine(to: CGPoint(x: point.x + 11, y: point.y))
            marker.move(to: CGPoint(x: point.x, y: point.y - 11)); marker.addLine(to: CGPoint(x: point.x, y: point.y + 11))
            slot.line.path = marker.cgPath; slot.line.strokeColor = UIColor.systemCyan.cgColor
            slot.dots.path = nil
            slot.label.text = " Point \(pointIndex + 1) "
            slot.label.textColor = .systemCyan
            slot.label.accessibilityIdentifier = "spatial.pending.\(pointIndex + 1)"
            slot.label.accessibilityLabel = "Pending measurement point \(pointIndex + 1)"
            slot.label.accessibilityValue = "Waiting for the next surface point"
            place(slot.label, near: CGPoint(x: point.x, y: point.y - 22))
        }
        CATransaction.commit()
    }

    /// One timer per visible overlay; incoming frames replace the deadline rather than enqueueing timers.
    private func armExpiry(at deadline: Double) {
        expiryDeadline = deadline
        guard expiryTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard let deadline = self.expiryDeadline, ProcessInfo.processInfo.systemUptime < deadline else {
                self.clear()
                return
            }
        }
        expiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func place(_ label: UILabel, near point: CGPoint) {
        label.sizeToFit()
        let size = CGSize(width: min(label.bounds.width, bounds.width), height: min(label.bounds.height, bounds.height))
        label.frame = CGRect(x: max(0, min(bounds.width - size.width, point.x - size.width / 2)),
                             y: max(0, min(bounds.height - size.height, point.y - size.height / 2)), width: size.width, height: size.height)
    }

    private func arrow(from start: CGPoint, to end: CGPoint) -> UIBezierPath {
        let path = UIBezierPath(); path.move(to: start); path.addLine(to: end)
        let dx = end.x - start.x, dy = end.y - start.y, length = hypot(dx, dy)
        guard length > 1 else { return path }
        let ux = dx / length, uy = dy / length, size = min(10, length * 0.25)
        path.move(to: CGPoint(x: end.x - ux * size - uy * size * 0.5, y: end.y - uy * size + ux * size * 0.5))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - ux * size + uy * size * 0.5, y: end.y - uy * size - ux * size * 0.5))
        return path
    }
}
