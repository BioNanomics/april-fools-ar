import UIKit

/// Passive, player-time overlays. Geometry is always in the recorded sensor
/// image; the live preview's cropping, zoom and wall-clock expiry do not apply.
final class RecordingPlaybackOverlayView: UIView {
    private var snapshot: RecordingPlaybackSnapshot?
    private var videoRect = CGRect.zero
    private var naturalSize = CGSize.zero
    private var preferredTransform = CGAffineTransform.identity
    private var labels: [String: UILabel] = [:]
    var showsTags = true {
        didSet {
            guard oldValue != showsTags else { return }
            updateLabels(); setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        accessibilityIdentifier = "recording.preview.overlays"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(snapshot: RecordingPlaybackSnapshot, videoRect: CGRect,
              naturalSize: CGSize, preferredTransform: CGAffineTransform) {
        self.snapshot = snapshot
        self.videoRect = videoRect
        self.naturalSize = naturalSize
        self.preferredTransform = preferredTransform
        updateLabels()
        setNeedsDisplay()
    }

    func clear() {
        snapshot = nil
        labels.values.forEach { $0.removeFromSuperview() }
        labels.removeAll()
        setNeedsDisplay()
    }

    /// `videoRect` is AVPlayerViewController.videoBounds converted into this
    /// view's coordinates, after the player has performed aspect-fit layout.
    static func imagePoint(_ point: CGPoint, imageSize: CGSize, naturalSize: CGSize,
                           preferredTransform transform: CGAffineTransform,
                           videoRect: CGRect) -> CGPoint? {
        guard finite(point), valid(imageSize), valid(naturalSize),
              valid(videoRect.size), finite(videoRect.origin),
              [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite),
              abs(transform.a * transform.d - transform.b * transform.c) > 1e-9 else { return nil }
        // A resolution change with the same sensor aspect ratio can be scaled;
        // a differently cropped image cannot be aligned reliably.
        let imageAspect = imageSize.width / imageSize.height
        let videoAspect = naturalSize.width / naturalSize.height
        guard abs(imageAspect / videoAspect - 1) < 0.001 else { return nil }
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        guard valid(oriented.size), finite(oriented.origin) else { return nil }
        let sensor = CGPoint(x: point.x / imageSize.width * naturalSize.width,
                             y: point.y / imageSize.height * naturalSize.height)
        let rotated = sensor.applying(transform)
        let mapped = CGPoint(x: videoRect.minX + (rotated.x - oriented.minX) / oriented.width * videoRect.width,
                             y: videoRect.minY + (rotated.y - oriented.minY) / oriented.height * videoRect.height)
        return finite(mapped) ? mapped : nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLabels()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let snapshot, let context = UIGraphicsGetCurrentContext(),
              videoRect.intersects(bounds) else { return }
        context.saveGState()
        context.clip(to: videoRect.intersection(bounds))
        defer { context.restoreGState() }
        for polygon in snapshot.polygons.prefix(96) {
            let points = mapped(polygon.points)
            guard points.count >= 3 else { continue }
            let path = UIBezierPath(); path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            let color = Self.color(polygon.style)
            color.withAlphaComponent(0.08).setFill(); path.fill()
            color.withAlphaComponent(0.8).setStroke(); path.lineWidth = 1.5
            path.setLineDash([6, 4], count: 2, phase: 0); path.stroke()
        }
        for line in snapshot.lines.prefix(512) {
            let points = mapped(line.points)
            guard points.count >= 2 else { continue }
            let color = Self.color(line.style), path = UIBezierPath()
            path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }
            path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            if line.style == "distance-horizontal" || line.style == "distance-vertical" {
                path.setLineDash([6, 4], count: 2, phase: 0)
            }
            color.setStroke(); path.stroke()
            color.setFill()
            for point in [points[0], points[points.count - 1]] {
                UIBezierPath(ovalIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
            }
        }
        for tag in snapshot.tags.prefix(showsTags ? 64 : 0) {
            let points = mapped(tag.corners)
            guard points.count == 4 else { continue }
            let color = Self.color(tag.severity), path = UIBezierPath()
            path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            color.withAlphaComponent(0.06).setFill(); path.fill()
            color.setStroke(); path.lineWidth = 2; path.lineJoinStyle = .round; path.stroke()
            color.setFill()
            for point in points {
                UIBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
            }
        }
    }

    private func mapped(_ points: [CGPoint]) -> [CGPoint] {
        guard let snapshot else { return [] }
        let result = points.compactMap {
            Self.imagePoint($0, imageSize: snapshot.imageSize, naturalSize: naturalSize,
                            preferredTransform: preferredTransform, videoRect: videoRect)
        }
        return result.count == points.count ? result : []
    }

    private func updateLabels() {
        guard let snapshot, validVideoRect else {
            labels.values.forEach { $0.isHidden = true }
            return
        }
        let clipping = videoRect.intersection(bounds).insetBy(dx: 6, dy: 6)
        guard clipping.width > 12, clipping.height > 12 else {
            labels.values.forEach { $0.isHidden = true }
            return
        }
        var used = Set<String>(), occupied: [CGRect] = []
        func place(_ key: String, _ text: String, _ anchor: CGPoint, _ color: UIColor,
                   identifier: String, avoidOverlap: Bool = true, accessibilityText: String? = nil) {
            guard !text.isEmpty, Self.finite(anchor) else { return }
            let label: UILabel
            if let existing = labels[key] { label = existing }
            else {
                label = UILabel()
                label.numberOfLines = 0
                label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
                label.backgroundColor = UIColor.black.withAlphaComponent(0.78)
                label.layer.cornerRadius = 4; label.clipsToBounds = true
                label.isAccessibilityElement = true
                label.isUserInteractionEnabled = false
                addSubview(label); labels[key] = label
            }
            used.insert(key)
            label.text = " \(text) "
            label.textColor = color
            label.accessibilityIdentifier = identifier
            label.accessibilityLabel = accessibilityText ?? text
            let maximum = CGSize(width: min(230, clipping.width), height: clipping.height)
            var size = label.sizeThatFits(maximum)
            size.width = min(maximum.width, ceil(size.width) + 4)
            size.height = min(maximum.height, ceil(size.height) + 4)
            var frame = CGRect(x: min(max(clipping.minX, anchor.x - size.width / 2), clipping.maxX - size.width),
                               y: min(max(clipping.minY, anchor.y), clipping.maxY - size.height),
                               width: size.width, height: size.height)
            if avoidOverlap {
                for _ in 0..<8 where occupied.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(frame) }) {
                    let down = frame.offsetBy(dx: 0, dy: size.height + 4)
                    if down.maxY <= clipping.maxY { frame = down }
                    else {
                        let up = frame.offsetBy(dx: 0, dy: -(size.height + 4))
                        if up.minY >= clipping.minY { frame = up } else { break }
                    }
                }
            }
            label.frame = frame; label.isHidden = false
            occupied.append(frame)
        }
        for tag in snapshot.tags.prefix(showsTags ? 64 : 0) {
            let points = mapped(tag.corners)
            guard points.count == 4, let extent = Self.enclosing(points), extent.intersects(videoRect) else { continue }
            place("tag.\(tag.id)", tag.label, CGPoint(x: extent.midX, y: extent.maxY + 7), Self.color(tag.severity),
                  identifier: "recording.preview.tag.\(tag.id)")
        }
        for line in snapshot.lines.prefix(512) {
            guard let label = line.label else { continue }
            let points = mapped(line.points)
            guard points.count >= 2, let extent = Self.enclosing(points), extent.insetBy(dx: -2, dy: -2).intersects(videoRect) else { continue }
            let first = points[0], last = points[points.count - 1]
            place("line.\(line.id)", label, CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2 - 16), Self.color(line.style),
                  identifier: "recording.preview.measurement.\(line.id)", accessibilityText: line.accessibilityLabel)
        }
        for polygon in snapshot.polygons.prefix(96) {
            guard let label = polygon.label else { continue }
            let points = mapped(polygon.points)
            guard points.count >= 3, let extent = Self.enclosing(points), extent.intersects(videoRect) else { continue }
            place("polygon.\(polygon.id)", label, CGPoint(x: extent.midX, y: extent.midY), Self.color(polygon.style),
                  identifier: polygon.style == "fieldExpected" ? "recording.preview.field.\(polygon.id)" : "recording.preview.floor.\(polygon.id)")
        }
        if let message = snapshot.message, !message.isEmpty {
            place("status", message, CGPoint(x: clipping.midX, y: clipping.maxY - 28), .white,
                  identifier: "recording.preview.overlay-status", avoidOverlap: false)
        }
        for key in Array(labels.keys) where !used.contains(key) {
            labels.removeValue(forKey: key)?.removeFromSuperview()
        }
    }

    private var validVideoRect: Bool {
        Self.valid(videoRect.size) && Self.finite(videoRect.origin) && videoRect.intersects(bounds)
    }
    private static func valid(_ size: CGSize) -> Bool { size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 }
    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func enclosing(_ points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
    private static func color(_ style: String) -> UIColor {
        switch style.lowercased().replacingOccurrences(of: "-", with: "") {
        case "good", "green": return .systemGreen
        case "warning", "distance", "measurement", "floortilted", "yellow": return .systemYellow
        case "bad", "axisx", "x", "red": return .systemRed
        case "axisy", "y": return .systemGreen
        case "axisz", "z", "blue": return .systemBlue
        case "distancehorizontal": return .systemCyan
        case "distancevertical": return .systemOrange
        case "height", "tagheight", "pending", "floor", "base", "selectedfloor", "cyan": return .systemCyan
        case "fieldexpected": return .systemTeal
        case "candidate", "orange": return .systemOrange
        default: return .lightGray
        }
    }
}
