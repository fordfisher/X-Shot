import AppKit
import Foundation

/// Draws annotation items into a graphics context (editor preview + export).
public enum AnnotationRenderer {
    public static func draw(document: AnnotationDocument, base: NSImage? = nil, in bounds: CGRect, context: NSGraphicsContext) {
        // Blurs first so they redact the photo under other marks.
        for item in document.items where item.tool == .blur {
            drawBlur(item: item, base: base, in: context)
        }
        for item in document.items where item.tool != .blur {
            draw(item: item, in: context)
        }
    }

    public static func draw(item: AnnotationItem, in context: NSGraphicsContext) {
        let color = ColorCodec.color(from: item.colorHex)
        let width = CGFloat(item.strokeWidth)

        switch item.tool {
        case .arrow:
            drawArrow(from: item.start, to: item.end, color: color, lineWidth: width)
        case .rectangle:
            strokeRect(item, color: color, lineWidth: width)
        case .ellipse:
            let rect = rect(of: item)
            let path = NSBezierPath(ovalIn: rect)
            color.setStroke()
            path.lineWidth = width
            path.stroke()
        case .pen:
            drawPolyline(item.points.map(\.cgPoint), color: color, lineWidth: width, alpha: 1)
        case .highlighter:
            drawPolyline(item.points.map(\.cgPoint), color: color, lineWidth: max(width * 3, 12), alpha: 0.35)
        case .text:
            drawText(item.text, at: item.start, color: color, fontSize: fontSize(for: item))
        case .callout:
            drawCallout(number: item.calloutNumber ?? 1, at: item.start, color: color, size: max(22, width * 6))
        case .blur, .crop, .move:
            break
        }
    }

    public static func composite(base: NSImage, document: AnnotationDocument) -> NSImage {
        let size = base.size
        let out = NSImage(size: size)
        out.lockFocus()
        defer { out.unlockFocus() }
        base.draw(in: CGRect(origin: .zero, size: size))
        if let ctx = NSGraphicsContext.current {
            draw(document: document, base: base, in: CGRect(origin: .zero, size: size), context: ctx)
        }
        return out
    }

    public static func boundingBox(of item: AnnotationItem) -> CGRect {
        switch item.tool {
        case .pen, .highlighter:
            let pts = item.points.map(\.cgPoint)
            guard let first = pts.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in pts.dropFirst() {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let pad = CGFloat(item.strokeWidth) * 2
            return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
        case .text:
            let font = NSFont.systemFont(ofSize: fontSize(for: item), weight: .semibold)
            let size = (item.text as NSString).size(withAttributes: [.font: font])
            return CGRect(x: item.start.x - 4, y: item.start.y - 2, width: max(size.width + 8, 40), height: max(size.height + 4, 20))
        case .callout:
            let s = max(22, item.strokeWidth * 6)
            return CGRect(x: item.start.x - s / 2, y: item.start.y - s / 2, width: s, height: s)
        case .arrow:
            let pad = CGFloat(item.strokeWidth) * 3
            return CGRect(
                x: min(item.start.x, item.end.x) - pad,
                y: min(item.start.y, item.end.y) - pad,
                width: abs(item.end.x - item.start.x) + pad * 2,
                height: abs(item.end.y - item.start.y) + pad * 2
            )
        default:
            return rect(of: item)
        }
    }

    public static func hitTest(document: AnnotationDocument, at point: CGPoint, tolerance: CGFloat = 8) -> UUID? {
        for item in document.items.reversed() {
            if item.tool == .crop || item.tool == .move { continue }
            if hitTest(item: item, at: point, tolerance: tolerance) {
                return item.id
            }
        }
        return nil
    }

    public static func hitTest(item: AnnotationItem, at point: CGPoint, tolerance: CGFloat) -> Bool {
        switch item.tool {
        case .arrow:
            return distanceToSegment(point, item.start, item.end) <= tolerance + CGFloat(item.strokeWidth)
        case .pen, .highlighter:
            let pts = item.points.map(\.cgPoint)
            guard pts.count >= 2 else { return false }
            let width = item.tool == .highlighter ? max(item.strokeWidth * 3, 12) : item.strokeWidth
            for i in 0..<(pts.count - 1) {
                if distanceToSegment(point, pts[i], pts[i + 1]) <= tolerance + CGFloat(width) {
                    return true
                }
            }
            return false
        default:
            return boundingBox(of: item).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    public static func fontSize(for item: AnnotationItem) -> CGFloat {
        max(14, CGFloat(item.strokeWidth) * 4)
    }

    public static func translated(_ item: AnnotationItem, by delta: CGPoint) -> AnnotationItem {
        var copy = item
        copy.points = item.points.map {
            CGPointCodable(x: $0.x + delta.x, y: $0.y + delta.y)
        }
        return copy
    }

    // MARK: - Private

    private static func rect(of item: AnnotationItem) -> CGRect {
        CGRect(
            x: min(item.start.x, item.end.x),
            y: min(item.start.y, item.end.y),
            width: abs(item.end.x - item.start.x),
            height: abs(item.end.y - item.start.y)
        )
    }

    private static func strokeRect(_ item: AnnotationItem, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath(rect: rect(of: item))
        color.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    private static func drawBlur(item: AnnotationItem, base: NSImage?, in context: NSGraphicsContext) {
        let r = rect(of: item).integral
        guard r.width >= 2, r.height >= 2, let base else { return }

        // Pixelate strength from stroke width (1…12 → ~6…40 px blocks).
        let block = max(6, Int(item.strokeWidth * 3.5))
        guard let pixelated = pixelate(base: base, rect: r, blockSize: block) else { return }
        pixelated.draw(in: r)

        // Subtle border so the redact region is visible while editing.
        NSColor.black.withAlphaComponent(0.15).setStroke()
        let border = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    /// Cheap Snagit-style pixelate redact (works without Core Image).
    public static func pixelate(base: NSImage, rect: CGRect, blockSize: Int) -> NSImage? {
        guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(cg.width) / base.size.width
        let scaleY = CGFloat(cg.height) / base.size.height
        // Canvas is flipped (y down); CGImage y is top-down — match AnnotationNSView flipped coords
        // by treating image space as top-left origin (same as our flipped view).
        let cgRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        guard cgRect.width >= 1, cgRect.height >= 1,
              let cropped = cg.cropping(to: cgRect) else { return nil }

        let outW = Int(rect.width)
        let outH = Int(rect.height)
        guard outW > 0, outH > 0 else { return nil }

        let smallW = max(1, outW / blockSize)
        let smallH = max(1, outH / blockSize)

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outW,
            pixelsHigh: outH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let src = NSImage(cgImage: cropped, size: NSSize(width: outW, height: outH))
        // Draw tiny then scale up with nearest-neighbor for chunky pixels.
        let tiny = NSImage(size: NSSize(width: smallW, height: smallH))
        tiny.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        src.draw(
            in: NSRect(x: 0, y: 0, width: smallW, height: smallH),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        tiny.unlockFocus()

        NSGraphicsContext.current?.imageInterpolation = .none
        tiny.draw(
            in: NSRect(x: 0, y: 0, width: outW, height: outH),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: outW, height: outH))
        image.addRepresentation(rep)
        return image
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        color.setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.stroke()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let head: CGFloat = max(10, lineWidth * 4)
        let p1 = CGPoint(x: to.x - head * cos(angle - .pi / 6), y: to.y - head * sin(angle - .pi / 6))
        let p2 = CGPoint(x: to.x - head * cos(angle + .pi / 6), y: to.y - head * sin(angle + .pi / 6))
        let headPath = NSBezierPath()
        headPath.move(to: to)
        headPath.line(to: p1)
        headPath.move(to: to)
        headPath.line(to: p2)
        headPath.lineWidth = lineWidth
        headPath.lineCapStyle = .round
        headPath.stroke()
    }

    private static func drawPolyline(_ points: [CGPoint], color: NSColor, lineWidth: CGFloat, alpha: CGFloat) {
        guard points.count >= 2 else { return }
        let path = NSBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawText(_ text: String, at point: CGPoint, color: NSColor, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        // Soft halo for readability on any background.
        let halo: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let ns = text as NSString
        for dx in [-1.0, 0.0, 1.0] {
            for dy in [-1.0, 0.0, 1.0] where dx != 0 || dy != 0 {
                ns.draw(at: CGPoint(x: point.x + dx, y: point.y + dy), withAttributes: halo)
            }
        }
        ns.draw(at: point, withAttributes: attrs)
    }

    private static func drawCallout(number: Int, at point: CGPoint, color: NSColor, size: CGFloat) {
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        let circle = NSBezierPath(ovalIn: rect)
        color.setFill()
        circle.fill()
        let label = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: size * 0.45),
            .foregroundColor: NSColor.white
        ]
        let s = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: point.x - s.width / 2, y: point.y - s.height / 2), withAttributes: attrs)
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        if len2 < 0.001 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2))
        let proj = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
