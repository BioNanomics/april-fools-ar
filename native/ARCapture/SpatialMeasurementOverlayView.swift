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
    private var automaticHeightSlots = [VectorSlot]()
    private var automaticHeightDeadlines = [Double]()
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
        automaticHeightSlots.forEach { $0.remove() }; automaticHeightSlots.removeAll(); automaticHeightDeadlines = []
        floorHitPaths.removeAll()
    }

    func floorPlaneID(at point: CGPoint) -> String? { floorHitPaths.reversed().first(where: { $0.1.contains(point) })?.0 }
    func floorID(at point: CGPoint) -> String? { floorPlaneID(at: point) }

    /// displayTransform already includes display magnification exactly once, like the tag renderer.
    func show(planes: [SpatialPlane], measurements: [SpatialMeasurement], pendingPoints: [SIMD3<Float>],
              selectedFloorID: String?, isTrackingNormal: Bool, cameraToWorld: simd_float4x4,
              intrinsics: simd_float3x3, imageSize: CGSize, displayTransform: CGAffineTransform, expiresAt: Double? = nil, showImperialHeight: Bool = true,
              pendingSelectedFloorID: String? = nil, automaticTagHeights: [TagHeightVector] = []) {
        let deadline = expiresAt ?? (ProcessInfo.processInfo.systemUptime + 0.5)
        guard deadline.isFinite, deadline > ProcessInfo.processInfo.systemUptime,
              isTrackingNormal, let camera = SpatialProjection.Camera(cameraToWorld: cameraToWorld,
              intrinsics: intrinsics, imageSize: imageSize, displayTransform: displayTransform, viewportSize: bounds.size) else { clear(); return }
        armExpiry(at: deadline)
        var planeGeometry = [(SpatialPlane, [CGPoint])]()
        // Preserve both confirmed and selected provisional planes when the candidate budget is full.
        func priority(_ plane: SpatialPlane) -> Int {
            plane.id == selectedFloorID ? 0 : (plane.id == pendingSelectedFloorID ? 1 : 2)
        }
        let candidates = planes.sorted { priority($0) < priority($1) }.prefix(24)
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
        let now = ProcessInfo.processInfo.systemUptime
        let automatic = automaticTagHeights.prefix(64).compactMap { vector -> (TagHeightVector, [CGPoint])? in
            guard vector.expiresAt > now, vector.heightMeters.isFinite, vector.heightMeters >= 0,
                  SpatialMeasurementMath.finite(vector.start), SpatialMeasurementMath.finite(vector.end),
                  let segment = camera.segment(from: vector.start, to: vector.end) else { return nil }
            return (vector, segment)
        }
        while planeSlots.count > planeGeometry.count { planeSlots.removeLast().remove() }
        while planeSlots.count < planeGeometry.count { planeSlots.append(PlaneSlot(in: self)) }
        while vectorSlots.count > vectors.count { vectorSlots.removeLast().remove() }
        while vectorSlots.count < vectors.count { vectorSlots.append(VectorSlot(in: self)) }
        while pendingSlots.count > pending.count { pendingSlots.removeLast().remove() }
        while pendingSlots.count < pending.count { pendingSlots.append(VectorSlot(in: self)) }
        while automaticHeightSlots.count > automatic.count { automaticHeightSlots.removeLast().remove() }
        while automaticHeightSlots.count < automatic.count { automaticHeightSlots.append(VectorSlot(in: self)) }
        automaticHeightDeadlines = automatic.map { $0.0.expiresAt }

        floorHitPaths.removeAll(keepingCapacity: true)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, geometry) in planeGeometry.enumerated() {
            let (plane, polygon) = geometry, slot = planeSlots[index]
            let selected = plane.id == selectedFloorID
            let pendingSelected = !selected && plane.id == pendingSelectedFloorID
            let classifiedFloor = plane.classification.lowercased() == "floor"
            let title = selected ? "Floor selected" : (pendingSelected ? "Floor candidate · scan to refine" : (classifiedFloor ? "Floor candidate" : "Horizontal surface"))
            let color: UIColor = selected ? .systemCyan : (pendingSelected ? .systemOrange : (classifiedFloor ? .systemTeal : .systemMint))
            let path = UIBezierPath(); path.move(to: polygon[0])
            polygon.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            slot.shape.path = path.cgPath; slot.shape.strokeColor = color.withAlphaComponent(0.8).cgColor
            slot.shape.fillColor = color.withAlphaComponent(selected || pendingSelected ? 0.15 : 0.06).cgColor
            slot.shape.lineWidth = selected || pendingSelected ? 2.5 : 1.5
            slot.shape.lineDashPattern = selected ? nil : [5, 4]
            slot.label.text = " \(title) "
            slot.label.textColor = color
            slot.label.accessibilityIdentifier = "spatial.plane.\(plane.id)"
            slot.label.accessibilityLabel = selected ? "Floor selected" : (pendingSelected ? "Selected floor candidate" : (classifiedFloor ? "Detected floor candidate" : "Horizontal surface candidate"))
            slot.label.accessibilityValue = selected ? "ID \(plane.id). Confirmed floor datum." : (pendingSelected ? "ID \(plane.id). Provisional selection. Continue scanning to refine, then choose Done to confirm." : "ID \(plane.id). Not confirmed.")
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
            let formattedHeight = isHeight ? HeightDisplayFormatter.string(meters: abs(vertical), showImperial: showImperialHeight) : nil
            slot.label.text = isHeight ? " Height \(formattedHeight ?? "—") " : String(format: " %.3f m · ΔY %.3f m ", distance, vertical)
            slot.label.textColor = color
            slot.label.font = .monospacedSystemFont(ofSize: isHeight ? 11 : 12, weight: isHeight ? .regular : .semibold)
            slot.label.accessibilityIdentifier = "spatial.measurement.\(measurement.id)"
            slot.label.accessibilityLabel = isHeight ? "Height measurement" : "Distance measurement"
            slot.label.accessibilityValue = isHeight ? "ID \(measurement.id). Height \(formattedHeight ?? "unavailable")." : String(format: "ID %@. Distance %.3f meters. Vertical difference %.3f meters.", measurement.id, distance, vertical)
            if isHeight { placeAtWorldMidpoint(slot.label, world: measurement.start+(measurement.end-measurement.start)/2, camera: camera) }
            else { slot.label.isHidden = false; place(slot.label, near: CGPoint(x: (segment[0].x + segment[1].x) / 2, y: (segment[0].y + segment[1].y) / 2 - 14)) }
        }
        for (index, geometry) in automatic.enumerated() {
            let (vector, segment) = geometry, slot = automaticHeightSlots[index]
            slot.line.isHidden = false; slot.dots.isHidden = false
            let color: UIColor = vector.severity == "warning" ? .systemYellow : .systemCyan
            slot.line.path = arrow(from: segment[0], to: segment[1]).cgPath
            slot.line.strokeColor = color.cgColor; slot.line.lineWidth = 1.5
            let dots = UIBezierPath()
            for world in [vector.start, vector.end] {
                if let point = camera.point(world), camera.viewport.contains(point) {
                    dots.append(UIBezierPath(ovalIn: CGRect(x: point.x-3, y: point.y-3, width: 6, height: 6)))
                }
            }
            slot.dots.path = dots.cgPath; slot.dots.fillColor = color.cgColor
            let height = HeightDisplayFormatter.string(meters: vector.heightMeters, showImperial: showImperialHeight) ?? "—"
            slot.label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            slot.label.text = " #\(vector.tagID) · \(height) "
            slot.label.textColor = color
            slot.label.accessibilityIdentifier = "spatial.tagHeight.\(index).\(vector.tagID)"
            slot.label.accessibilityLabel = "Tag \(vector.tagID) height above floor"
            slot.label.accessibilityValue = "\(height). \(vector.source == "sceneDepth" ? "LiDAR" : "Tag pose estimate")."
            placeAtWorldMidpoint(slot.label, world: vector.midpoint, camera: camera)
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
            let now = ProcessInfo.processInfo.systemUptime
            for (index, expiresAt) in self.automaticHeightDeadlines.enumerated() where expiresAt <= now && index < self.automaticHeightSlots.count {
                let slot = self.automaticHeightSlots[index]
                slot.line.isHidden = true; slot.dots.isHidden = true; slot.label.isHidden = true
            }
        }
        expiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func placeAtWorldMidpoint(_ label: UILabel, world: SIMD3<Float>, camera: SpatialProjection.Camera) {
        guard let point = camera.point(world), camera.viewport.contains(point) else { label.isHidden = true; return }
        label.isHidden = false; label.sizeToFit()
        // Do not clamp an offscreen world anchor into a misleading visible location.
        label.center = point
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
