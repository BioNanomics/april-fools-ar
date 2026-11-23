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
        let line = CAShapeLayer(), dots = CAShapeLayer(), basePatch = CAShapeLayer()
        let label = UILabel()
        init(in view: UIView) {
            line.lineWidth = 2.5; line.lineCap = .round; line.lineJoin = .round
            line.fillColor = UIColor.clear.cgColor
            line.shadowColor = UIColor.black.cgColor; line.shadowOpacity = 0.8; line.shadowRadius = 1; line.shadowOffset = .zero
            dots.lineWidth = 1.5; dots.strokeColor = UIColor.black.cgColor
            basePatch.fillColor = UIColor.clear.cgColor
            basePatch.lineWidth = 1.5; basePatch.lineCap = .round; basePatch.lineJoin = .round
            basePatch.lineDashPattern = [1, 4]; basePatch.isHidden = true
            basePatch.shadowColor = UIColor.black.cgColor; basePatch.shadowOpacity = 0.8
            basePatch.shadowRadius = 1; basePatch.shadowOffset = .zero
            view.layer.addSublayer(basePatch); view.layer.addSublayer(line); view.layer.addSublayer(dots)
            SpatialMeasurementOverlayView.style(label)
            view.addSubview(label)
        }
        func remove() { label.removeFromSuperview(); line.removeFromSuperlayer(); dots.removeFromSuperlayer(); basePatch.removeFromSuperlayer() }
    }
    private final class DistanceTriangleSlot {
        let horizontal = CAShapeLayer(), vertical = CAShapeLayer()
        let horizontalLabel = UILabel(), verticalLabel = UILabel()
        init(in view: UIView) {
            for shape in [horizontal, vertical] {
                shape.lineWidth = 1.5; shape.lineCap = .round; shape.lineDashPattern = [5, 4]
                shape.fillColor = UIColor.clear.cgColor
                shape.shadowColor = UIColor.black.cgColor; shape.shadowOpacity = 0.8
                shape.shadowRadius = 1; shape.shadowOffset = .zero
                view.layer.addSublayer(shape)
            }
            for label in [horizontalLabel, verticalLabel] {
                SpatialMeasurementOverlayView.style(label)
                view.addSubview(label)
            }
        }
        func remove() {
            horizontal.removeFromSuperlayer(); vertical.removeFromSuperlayer()
            horizontalLabel.removeFromSuperview(); verticalLabel.removeFromSuperview()
        }
    }
    private var planeSlots = [PlaneSlot]()
    private var vectorSlots = [VectorSlot]()
    private var distanceTriangleSlots = [DistanceTriangleSlot]()
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
        distanceTriangleSlots.forEach { $0.remove() }; distanceTriangleSlots.removeAll()
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
        var vectors = [(SpatialMeasurement, [CGPoint]?, SpatialDistanceTriangle?, [CGPoint]?, [CGPoint]?)]()
        for measurement in measurements.suffix(50) {
            guard measurement.distanceMeters.isFinite, measurement.verticalMeters.isFinite else { continue }
            let diagonal = camera.segment(from: measurement.start, to: measurement.end)
            if measurement.kind == "distance" {
                guard let triangle = SpatialMeasurementMath.distanceTriangle(from: measurement.start, to: measurement.end) else { continue }
                // Each original edge is clipped separately; a visible leg does not depend on the diagonal.
                let hasLegs = triangle.horizontalMeters > 1e-6 && abs(triangle.verticalMeters) > 1e-6
                let horizontal = hasLegs ? camera.segment(from: measurement.start, to: triangle.corner) : nil
                let vertical = hasLegs ? camera.segment(from: triangle.corner, to: measurement.end) : nil
                guard diagonal != nil || horizontal != nil || vertical != nil else { continue }
                vectors.append((measurement, diagonal, triangle, horizontal, vertical))
            } else if let diagonal {
                vectors.append((measurement, diagonal, nil, nil, nil))
            }
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
        let triangleCount = vectors.filter { $0.2 != nil }.count
        while distanceTriangleSlots.count > triangleCount { distanceTriangleSlots.removeLast().remove() }
        while distanceTriangleSlots.count < triangleCount { distanceTriangleSlots.append(DistanceTriangleSlot(in: self)) }
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
        var triangleIndex = 0
        for (index, geometry) in vectors.enumerated() {
            let (measurement, segment, triangle, horizontalSegment, verticalSegment) = geometry, slot = vectorSlots[index]
            let isHeight = measurement.kind == "height", color: UIColor = isHeight ? .systemOrange : .systemYellow
            slot.line.name = "spatial.measurement.\(measurement.id).diagonal"
            slot.line.path = segment.map { arrow(from: $0[0], to: $0[1]).cgPath }
            slot.line.isHidden = segment == nil
            slot.line.strokeColor = color.cgColor; slot.dots.fillColor = color.cgColor
            let dots = UIBezierPath()
            for world in [measurement.start, measurement.end] {
                if let point = camera.point(world), camera.viewport.contains(point) {
                    dots.append(UIBezierPath(ovalIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)))
                }
            }
            slot.dots.path = dots.cgPath
            let distance = triangle?.distanceMeters ?? Double(measurement.distanceMeters)
            let vertical = triangle?.verticalMeters ?? Double(measurement.verticalMeters)
            let formattedHeight = isHeight ? HeightDisplayFormatter.string(meters: abs(vertical), showImperial: showImperialHeight) : nil
            slot.label.text = isHeight ? " Height \(formattedHeight ?? "—") " : String(format: " %.3f m · ΔY %.3f m ", distance, vertical)
            slot.label.textColor = color
            slot.label.font = .monospacedSystemFont(ofSize: isHeight ? 11 : 12, weight: isHeight ? .regular : .semibold)
            slot.label.numberOfLines = 1
            slot.label.lineBreakMode = .byTruncatingTail
            slot.label.accessibilityIdentifier = "spatial.measurement.\(measurement.id)"
            slot.label.accessibilityLabel = isHeight ? "Height measurement" : "Distance measurement"
            slot.label.accessibilityValue = isHeight ? "ID \(measurement.id). Height \(formattedHeight ?? "unavailable")." : String(format: "ID %@. Distance %.3f meters. Vertical difference %.3f meters.", measurement.id, distance, vertical)
            if let triangle {
                let triangleSlot = distanceTriangleSlots[triangleIndex]; triangleIndex += 1
                let horizontalIsZero = triangle.horizontalMeters <= 1e-6, verticalIsZero = abs(triangle.verticalMeters) <= 1e-6
                var directText = String(format: " D %.3f m", triangle.distanceMeters)
                if horizontalIsZero || verticalIsZero {
                    directText += String(format: " · H %.3f m · V %+.3f m", triangle.horizontalMeters, triangle.verticalMeters)
                    slot.label.numberOfLines = 0
                    slot.label.lineBreakMode = .byWordWrapping
                }
                slot.label.text = directText + " "
                slot.label.accessibilityValue = String(format: "ID %@. Direct distance %.3f meters. Horizontal distance %.3f meters. Signed vertical difference %+.3f meters. Horizontal is level with gravity; positive vertical is upward.", measurement.id, triangle.distanceMeters, triangle.horizontalMeters, triangle.verticalMeters)
                showTriangleLeg(triangleSlot.horizontal, label: triangleSlot.horizontalLabel, segment: horizontalSegment,
                    opposite: measurement.end, camera: camera, color: .systemCyan,
                    text: String(format: " H %.3f m ", triangle.horizontalMeters),
                    identifier: "spatial.measurement.\(measurement.id).horizontal", accessibility: "Horizontal distance",
                    value: String(format: "%.3f meters. Level with gravity.", triangle.horizontalMeters))
                showTriangleLeg(triangleSlot.vertical, label: triangleSlot.verticalLabel, segment: verticalSegment,
                    opposite: measurement.start, camera: camera, color: .systemOrange,
                    text: String(format: " V %+.3f m ", triangle.verticalMeters),
                    identifier: "spatial.measurement.\(measurement.id).vertical", accessibility: "Signed vertical difference",
                    value: String(format: "%+.3f meters. Positive is upward along gravity-aligned vertical.", triangle.verticalMeters))
            }
            if isHeight {
                let state = showFloorBase(slot, center: measurement.start, floor: measurement.floor,
                    camera: camera, owner: "manual.\(measurement.id)")
                slot.label.accessibilityValue = (slot.label.accessibilityValue ?? "") + " " + baseAccessibility(state)
            } else { hideFloorBase(slot) }
            if isHeight { placeAtWorldMidpoint(slot.label, world: measurement.start+(measurement.end-measurement.start)/2, camera: camera) }
            else if let anchor = segment ?? horizontalSegment ?? verticalSegment {
                slot.label.isHidden = false
                if let triangle {
                    place(slot.label, near: edgeLabelPoint(anchor, opposite: camera.point(triangle.corner)))
                } else {
                    place(slot.label, near: CGPoint(x: (anchor[0].x + anchor[1].x) / 2, y: (anchor[0].y + anchor[1].y) / 2 - 14))
                }
            }
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
            let state = showFloorBase(slot, center: vector.start, floor: vector.floor,
                camera: camera, owner: "tag.\(index).\(vector.tagID)")
            slot.label.accessibilityValue = (slot.label.accessibilityValue ?? "") + " " + baseAccessibility(state)
            placeAtWorldMidpoint(slot.label, world: vector.midpoint, camera: camera)
        }
        for (slotIndex, pointData) in pending.enumerated() {
            let (pointIndex, point) = pointData, slot = pendingSlots[slotIndex]
            hideFloorBase(slot)
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

    private func showTriangleLeg(_ shape: CAShapeLayer, label: UILabel, segment: [CGPoint]?, opposite: SIMD3<Float>,
                                 camera: SpatialProjection.Camera, color: UIColor, text: String,
                                 identifier: String, accessibility: String, value: String) {
        shape.name = identifier
        shape.strokeColor = color.cgColor
        label.text = text; label.textColor = color
        label.accessibilityIdentifier = identifier
        label.accessibilityLabel = accessibility; label.accessibilityValue = value
        // Open, independently clipped edges preserve their world-space meaning at the viewport boundary.
        guard let segment else { shape.path = nil; shape.isHidden = true; label.isHidden = true; return }
        let path = UIBezierPath(); path.move(to: segment[0]); path.addLine(to: segment[1])
        shape.path = path.cgPath; shape.isHidden = false; label.isHidden = false
        place(label, near: edgeLabelPoint(segment, opposite: camera.point(opposite)))
    }

    private func edgeLabelPoint(_ segment: [CGPoint], opposite: CGPoint?) -> CGPoint {
        let midpoint = CGPoint(x: (segment[0].x + segment[1].x) / 2, y: (segment[0].y + segment[1].y) / 2)
        let dx = segment[1].x - segment[0].x, dy = segment[1].y - segment[0].y
        let length = hypot(dx, dy)
        guard length > 1e-6 else { return CGPoint(x: midpoint.x, y: midpoint.y - 14) }
        var nx = -dy / length, ny = dx / length
        if let opposite, nx * (opposite.x - midpoint.x) + ny * (opposite.y - midpoint.y) > 0 { nx = -nx; ny = -ny }
        return CGPoint(x: midpoint.x + nx * 16, y: midpoint.y + ny * 16)
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
                slot.line.isHidden = true; slot.dots.isHidden = true; slot.basePatch.isHidden = true; slot.label.isHidden = true
            }
        }
        expiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func hideFloorBase(_ slot: VectorSlot) {
        slot.basePatch.path = nil; slot.basePatch.isHidden = true; slot.basePatch.name = nil
    }
    private func showFloorBase(_ slot: VectorSlot, center: SIMD3<Float>, floor: SpatialPlane?,
                               camera: SpatialProjection.Camera, owner: String) -> FloorBaseMarker.State {
        guard let floor, let marker = FloorBaseMarker.make(center: center, floor: floor) else {
            hideFloorBase(slot); return .unknown
        }
        let path = UIBezierPath()
        var visibleEdges = 0
        // Clip the original edges independently. Closing a clipped polygon would invent viewport/near-plane edges.
        for index in 0..<4 {
            guard let segment = camera.segment(from: marker.corners[index], to: marker.corners[(index + 1) % 4]) else { continue }
            path.move(to: segment[0]); path.addLine(to: segment[1]); visibleEdges += 1
        }
        slot.basePatch.name = "spatial.floorBase.\(owner)"
        slot.basePatch.path = visibleEdges > 0 ? path.cgPath : nil
        slot.basePatch.isHidden = visibleEdges == 0
        let color: UIColor
        switch marker.state { case .level: color = .systemGreen; case .tilted: color = .systemYellow; case .unknown: color = .lightGray }
        slot.basePatch.strokeColor = color.cgColor
        return marker.state
    }
    private func baseAccessibility(_ state: FloorBaseMarker.State) -> String {
        switch state {
        case .level: return "Base plane level."
        case .tilted: return "Base plane tilted."
        case .unknown: return "Base plane tilt unavailable."
        }
    }
    private func placeAtWorldMidpoint(_ label: UILabel, world: SIMD3<Float>, camera: SpatialProjection.Camera) {
        guard let point = camera.point(world), camera.viewport.contains(point) else { label.isHidden = true; return }
        label.isHidden = false; label.sizeToFit()
        // Do not clamp an offscreen world anchor into a misleading visible location.
        label.center = point
    }

    private func place(_ label: UILabel, near point: CGPoint) {
        let natural = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let width = min(ceil(natural.width), bounds.width)
        // Degenerate distance summaries retain all three values when the viewport needs multiple lines.
        let fittedHeight = label.numberOfLines == 1 ? natural.height
            : label.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        let size = CGSize(width: width, height: min(ceil(fittedHeight), bounds.height))
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
