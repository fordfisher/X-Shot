import AppKit
import Combine
import Foundation

@MainActor
public final class EditorSession: ObservableObject {
    public let shotID: UUID
    @Published public var baseImage: NSImage

    @Published public var document: AnnotationDocument
    @Published public var tool: AnnotationTool = .arrow
    @Published public var colorHex: String = XShotTheme.defaultStrokeHex
    @Published public var strokeWidth: Double = 3
    @Published public var isDirty: Bool = false
    @Published public var draft: AnnotationItem?
    @Published public var selectedID: UUID?
    @Published public var cropRect: CGRect?
    /// True when the base bitmap was replaced (e.g. crop) and originals must be rewritten on save.
    public var baseReplaced: Bool = false

    private var undoStack: [AnnotationDocument] = []
    private var redoStack: [AnnotationDocument] = []
    private let maxUndo = 50

    /// Move-tool drag state.
    private var moveStartPoint: CGPoint?
    private var moveOriginalItem: AnnotationItem?

    public init(shotID: UUID, baseImage: NSImage, document: AnnotationDocument = AnnotationDocument()) {
        self.shotID = shotID
        self.baseImage = baseImage
        self.document = document
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func selectTool(_ newTool: AnnotationTool) {
        guard tool != newTool else { return }
        // Drop in-progress shape / blur / crop draft when switching tools.
        if draft?.tool != .crop || newTool != .crop {
            draft = nil
        }
        if newTool != .crop {
            cropRect = nil
        }
        tool = newTool
    }

    public func beginStroke(at point: CGPoint) {
        switch tool {
        case .move:
            beginMove(at: point)
        case .pen, .highlighter:
            draft = AnnotationItem(
                tool: tool,
                colorHex: tool == .highlighter ? XShotTheme.highlighterHex : colorHex,
                strokeWidth: strokeWidth,
                points: [CGPointCodable(point)]
            )
        case .callout:
            var doc = document
            pushUndo()
            let item = AnnotationItem(
                tool: .callout,
                colorHex: colorHex,
                strokeWidth: strokeWidth,
                points: [CGPointCodable(point)],
                calloutNumber: doc.nextCalloutNumber
            )
            doc.items.append(item)
            doc.nextCalloutNumber += 1
            document = doc
            selectedID = item.id
            isDirty = true
        case .text:
            break
        case .crop:
            cropRect = CGRect(origin: point, size: .zero)
        case .blur, .arrow, .rectangle, .ellipse:
            draft = AnnotationItem(
                tool: tool,
                colorHex: tool == .blur ? "#000000" : colorHex,
                strokeWidth: strokeWidth,
                points: [CGPointCodable(point), CGPointCodable(point)]
            )
        }
    }

    public func continueStroke(to point: CGPoint) {
        if tool == .move {
            continueMove(to: point)
            return
        }
        if tool == .crop, let r = cropRect {
            let origin = r.origin
            cropRect = CGRect(
                x: min(origin.x, point.x),
                y: min(origin.y, point.y),
                width: abs(point.x - origin.x),
                height: abs(point.y - origin.y)
            )
            return
        }
        guard var d = draft else { return }
        if d.tool == .pen || d.tool == .highlighter {
            d.points.append(CGPointCodable(point))
        } else if d.points.count >= 2 {
            d.points[1] = CGPointCodable(point)
        } else {
            d.points.append(CGPointCodable(point))
        }
        draft = d
    }

    public func endStroke() {
        if tool == .move {
            endMove()
            return
        }
        guard let d = draft else {
            cropRect = nil
            return
        }
        if d.tool == .crop {
            draft = nil
            return
        }
        // Ignore tiny blur/rect clicks
        if d.tool == .blur || d.tool == .rectangle || d.tool == .ellipse {
            let r = AnnotationRenderer.boundingBox(of: d)
            if r.width < 4 || r.height < 4 {
                draft = nil
                return
            }
        }
        pushUndo()
        document.items.append(d)
        selectedID = d.id
        draft = nil
        isDirty = true
    }

    // MARK: - Move

    public func beginMove(at point: CGPoint) {
        guard let id = AnnotationRenderer.hitTest(document: document, at: point),
              let item = document.items.first(where: { $0.id == id }) else {
            selectedID = nil
            moveStartPoint = nil
            moveOriginalItem = nil
            return
        }
        selectedID = id
        moveStartPoint = point
        moveOriginalItem = item
    }

    public func continueMove(to point: CGPoint) {
        guard let start = moveStartPoint,
              let original = moveOriginalItem,
              let idx = document.items.firstIndex(where: { $0.id == original.id }) else { return }
        // First drag movement commits an undo checkpoint once.
        if document.items[idx] == original {
            pushUndo()
        }
        let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
        document.items[idx] = AnnotationRenderer.translated(original, by: delta)
        isDirty = true
    }

    public func endMove() {
        moveStartPoint = nil
        moveOriginalItem = nil
    }

    // MARK: - Text

    public func addText(_ text: String, at point: CGPoint) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pushUndo()
        let item = AnnotationItem(
            tool: .text,
            colorHex: colorHex,
            strokeWidth: strokeWidth,
            points: [CGPointCodable(point)],
            text: trimmed
        )
        document.items.append(item)
        selectedID = item.id
        isDirty = true
    }

    public func updateText(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = document.items.firstIndex(where: { $0.id == id }) else { return }
        if trimmed.isEmpty {
            pushUndo()
            document.items.remove(at: idx)
            if selectedID == id { selectedID = nil }
            isDirty = true
            return
        }
        guard document.items[idx].text != trimmed else { return }
        pushUndo()
        document.items[idx].text = trimmed
        isDirty = true
    }

    public func textItem(at point: CGPoint) -> AnnotationItem? {
        guard let id = AnnotationRenderer.hitTest(document: document, at: point),
              let item = document.items.first(where: { $0.id == id }),
              item.tool == .text else { return nil }
        return item
    }

    public func deleteSelected() {
        guard let id = selectedID,
              let idx = document.items.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        document.items.remove(at: idx)
        selectedID = nil
        isDirty = true
    }

    // MARK: - Undo / crop / export

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        isDirty = true
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        isDirty = true
    }

    public func clearAnnotations() {
        guard !document.items.isEmpty else { return }
        pushUndo()
        document = AnnotationDocument()
        selectedID = nil
        isDirty = true
    }

    @discardableResult
    public func applyCrop() -> Bool {
        guard let d = draft, d.tool == .crop else { return false }
        let rect = CGRect(
            x: min(d.start.x, d.end.x),
            y: min(d.start.y, d.end.y),
            width: abs(d.end.x - d.start.x),
            height: abs(d.end.y - d.start.y)
        ).integral
        guard rect.width >= 4, rect.height >= 4 else { return false }
        guard let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let scaleX = CGFloat(cg.width) / baseImage.size.width
        let scaleY = CGFloat(cg.height) / baseImage.size.height
        let cgRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let cropped = cg.cropping(to: cgRect) else { return false }
        baseImage = NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        document = AnnotationDocument()
        draft = nil
        selectedID = nil
        undoStack.removeAll()
        redoStack.removeAll()
        isDirty = true
        baseReplaced = true
        tool = .arrow
        return true
    }

    public func renderedImage() -> NSImage {
        AnnotationRenderer.composite(base: baseImage, document: displayDocument())
    }

    public func displayDocument() -> AnnotationDocument {
        var doc = document
        if let draft { doc.items.append(draft) }
        return doc
    }

    public func copyToClipboard() {
        ScreenCaptureService.copyToClipboard(renderedImage())
    }

    private func pushUndo() {
        undoStack.append(document)
        if undoStack.count > maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
    }
}
