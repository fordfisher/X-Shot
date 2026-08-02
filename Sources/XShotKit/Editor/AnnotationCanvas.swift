import AppKit
import SwiftUI

struct AnnotationCanvasView: NSViewRepresentable {
    @ObservedObject var session: EditorSession

    func makeNSView(context: Context) -> AnnotationNSView {
        let view = AnnotationNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: AnnotationNSView, context: Context) {
        nsView.session = session
        nsView.window?.invalidateCursorRects(for: nsView)
        nsView.needsDisplay = true
        if session.tool != .text {
            nsView.commitTextEditorIfNeeded()
        }
    }
}

final class AnnotationNSView: NSView, NSTextViewDelegate {
    var session: EditorSession? {
        didSet { needsDisplay = true }
    }

    private var imageRectInView: CGRect = .zero
    private var cropStart: CGPoint?

    private var textScroll: NSScrollView?
    private var textView: NSTextView?
    private var editingTextID: UUID?
    private var editingImagePoint: CGPoint = .zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let session else { return }
        let image = session.baseImage
        imageRectInView = Self.aspectFit(imageSize: image.size, in: bounds.insetBy(dx: 24, dy: 24))

        NSColor(xshotHex: XShotTheme.workspaceHex).setFill()
        bounds.fill()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: 4)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        imageRectInView.fill()
        NSGraphicsContext.restoreGraphicsState()

        image.draw(in: imageRectInView)

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        let cg = ctx.cgContext
        let scaleX = imageRectInView.width / max(session.baseImage.size.width, 1)
        let scaleY = imageRectInView.height / max(session.baseImage.size.height, 1)
        cg.translateBy(x: imageRectInView.minX, y: imageRectInView.minY)
        cg.scaleBy(x: scaleX, y: scaleY)
        AnnotationRenderer.draw(
            document: session.displayDocument(),
            base: session.baseImage,
            in: CGRect(origin: .zero, size: image.size),
            context: ctx
        )

        if let selectedID = session.selectedID,
           let item = session.document.items.first(where: { $0.id == selectedID }) {
            let box = AnnotationRenderer.boundingBox(of: item).insetBy(dx: -3, dy: -3)
            NSColor(xshotHex: XShotTheme.accentHex).withAlphaComponent(0.9).setStroke()
            let path = NSBezierPath(rect: box)
            path.lineWidth = 1 / max(scaleX, 0.001)
            path.setLineDash([4 / scaleX, 3 / scaleX], count: 2, phase: 0)
            path.stroke()
        }
        ctx.restoreGraphicsState()

        if session.tool == .crop, let draft = session.draft, draft.tool == .crop {
            let r = viewRect(for: draft)
            NSColor.black.withAlphaComponent(0.35).setFill()
            bounds.fill()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            r.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor(xshotHex: XShotTheme.accentHex).setStroke()
            let border = NSBezierPath(rect: r)
            border.lineWidth = 2
            border.stroke()
        }

        if session.tool == .blur, let draft = session.draft, draft.tool == .blur {
            let r = viewRect(for: draft)
            NSColor(xshotHex: XShotTheme.accentHex).withAlphaComponent(0.25).setFill()
            r.fill()
            NSColor(xshotHex: XShotTheme.accentHex).setStroke()
            let border = NSBezierPath(rect: r)
            border.lineWidth = 1.5
            border.setLineDash([4, 3], count: 2, phase: 0)
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let session else { return }

        if textView != nil {
            commitTextEditorIfNeeded()
        }

        let p = convert(event.locationInWindow, from: nil)
        let imagePoint = viewToImage(p)
        guard imageRectInView.contains(p) || session.tool == .crop else { return }

        if session.tool == .text {
            if event.clickCount >= 2, let existing = session.textItem(at: imagePoint) {
                beginTextEditing(item: existing)
            } else if let existing = session.textItem(at: imagePoint) {
                session.selectedID = existing.id
                needsDisplay = true
            } else {
                beginTextEditing(at: imagePoint, existing: nil)
            }
            return
        }

        if session.tool == .move, event.clickCount >= 2,
           let existing = session.textItem(at: imagePoint) {
            session.tool = .text
            beginTextEditing(item: existing)
            return
        }

        if session.tool == .crop {
            session.beginStroke(at: imagePoint)
            session.draft = AnnotationItem(
                tool: .crop,
                colorHex: XShotTheme.accentHex,
                strokeWidth: 1,
                points: [CGPointCodable(imagePoint), CGPointCodable(imagePoint)]
            )
            cropStart = imagePoint
            needsDisplay = true
            return
        }

        session.beginStroke(at: imagePoint)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session else { return }
        let p = convert(event.locationInWindow, from: nil)
        let imagePoint = viewToImage(p)
        session.continueStroke(to: imagePoint)
        if session.tool == .crop, var d = session.draft, let start = cropStart {
            d.points = [CGPointCodable(start), CGPointCodable(imagePoint)]
            session.draft = d
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let session else { return }
        if session.tool == .crop {
            needsDisplay = true
            return
        }
        session.endStroke()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Inline text editor owns typing — never steal letter shortcuts there.
        if textView != nil {
            super.keyDown(with: event)
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            super.keyDown(with: event)
            return
        }
        // Delete / Backspace removes selection
        if event.keyCode == 51 || event.keyCode == 117 {
            session?.deleteSelected()
            needsDisplay = true
            return
        }
        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           let ch = chars.first,
           let tool = AnnotationTool.fromShortcutKey(ch) {
            session?.selectTool(tool)
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let session else {
            NSCursor.arrow.set()
            return
        }
        switch session.tool {
        case .move: NSCursor.openHand.set()
        case .text: NSCursor.iBeam.set()
        case .blur, .crop: NSCursor.crosshair.set()
        default: NSCursor.crosshair.set()
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        guard let session else { return }
        let cursor: NSCursor
        switch session.tool {
        case .move: cursor = .openHand
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Inline text editor

    private func beginTextEditing(item: AnnotationItem) {
        beginTextEditing(at: item.start, existing: item)
    }

    private func beginTextEditing(at imagePoint: CGPoint, existing: AnnotationItem?) {
        commitTextEditorIfNeeded()
        editingTextID = existing?.id
        editingImagePoint = imagePoint
        if let existing {
            session?.selectedID = existing.id
        }

        let fontSize = existing.map { AnnotationRenderer.fontSize(for: $0) }
            ?? max(14, CGFloat(session?.strokeWidth ?? 3) * 4)
        let color = ColorCodec.color(from: existing?.colorHex ?? session?.colorHex ?? XShotTheme.defaultStrokeHex)

        let origin = imageToView(imagePoint)
        let width = max(220, imageRectInView.maxX - origin.x - 8)
        let height: CGFloat = max(48, fontSize * 2.4)

        let scroll = NSScrollView(frame: NSRect(x: origin.x, y: origin.y, width: min(width, 420), height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .lineBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.96)

        let tv = NSTextView(frame: scroll.contentView.bounds)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        tv.textColor = color
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.string = existing?.text ?? ""
        tv.delegate = self
        tv.insertionPointColor = color

        scroll.documentView = tv
        addSubview(scroll)
        window?.makeFirstResponder(tv)

        textScroll = scroll
        textView = tv
        needsDisplay = true
    }

    func commitTextEditorIfNeeded() {
        guard let tv = textView else { return }
        let text = tv.string
        let point = editingImagePoint
        let id = editingTextID

        textScroll?.removeFromSuperview()
        textScroll = nil
        textView = nil
        editingTextID = nil

        if let id {
            session?.updateText(id: id, text: text)
        } else {
            session?.addText(text, at: point)
        }
        needsDisplay = true
    }

    func textDidEndEditing(_ notification: Notification) {
        commitTextEditorIfNeeded()
    }

    // MARK: - Coords

    private func viewRect(for item: AnnotationItem) -> CGRect {
        let a = imageToView(item.start)
        let b = imageToView(item.end)
        return CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private func viewToImage(_ p: CGPoint) -> CGPoint {
        guard let session else { return p }
        let s = session.baseImage.size
        let r = imageRectInView
        guard r.width > 0, r.height > 0 else { return .zero }
        return CGPoint(
            x: (p.x - r.minX) / r.width * s.width,
            y: (p.y - r.minY) / r.height * s.height
        )
    }

    private func imageToView(_ p: CGPoint) -> CGPoint {
        guard let session else { return p }
        let s = session.baseImage.size
        let r = imageRectInView
        guard s.width > 0, s.height > 0 else { return .zero }
        return CGPoint(
            x: r.minX + p.x / s.width * r.width,
            y: r.minY + p.y / s.height * r.height
        )
    }

    static func aspectFit(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: bounds.midX - w / 2,
            y: bounds.midY - h / 2,
            width: w,
            height: h
        )
    }
}
