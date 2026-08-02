import AppKit

public protocol RegionPickerDelegate: AnyObject {
    @MainActor func regionPickerDidSelect(_ rect: CGRect)
    @MainActor func regionPickerDidCancel()
}

/// Fullscreen dimmed overlay for drag-to-select region capture.
@MainActor
public final class RegionPickerController: NSObject {
    public weak var delegate: RegionPickerDelegate?
    private var overlays: [RegionPickerOverlay] = []

    public override init() {
        super.init()
    }

    public func begin() {
        tearDownOverlays()
        for screen in NSScreen.screens {
            let overlay = RegionPickerOverlay(screen: screen)
            overlay.onSelect = { [weak self] globalRect in
                guard let self else { return }
                // Hide first so we aren't capturing our own chrome, then finish
                // on the next turn so mouse-up can unwind safely.
                self.hideOverlays()
                DispatchQueue.main.async {
                    self.delegate?.regionPickerDidSelect(globalRect)
                    self.tearDownOverlays()
                }
            }
            overlay.onCancel = { [weak self] in
                guard let self else { return }
                self.hideOverlays()
                DispatchQueue.main.async {
                    self.delegate?.regionPickerDidCancel()
                    self.tearDownOverlays()
                }
            }
            overlays.append(overlay)
            overlay.show()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    public func cancelOverlays() {
        hideOverlays()
        tearDownOverlays()
    }

    private func hideOverlays() {
        overlays.forEach { $0.hide() }
    }

    private func tearDownOverlays() {
        overlays.forEach { $0.tearDown() }
        overlays.removeAll()
    }
}

final class RegionPickerOverlay {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let window: NSWindow
    private let canvas: RegionPickerView

    init(screen: NSScreen) {
        let canvas = RegionPickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        self.canvas = canvas

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // We own the window; AppKit must not release it on close.
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false
        window.contentView = canvas
        self.window = window

        canvas.onSelect = { [weak self] rectInWindow in
            guard let self else { return }
            let screenRect = self.window.convertToScreen(rectInWindow)
            self.onSelect?(screenRect)
        }
        canvas.onCancel = { [weak self] in
            self?.onCancel?()
        }
    }

    func show() {
        window.setFrame(window.screen?.frame ?? window.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    func hide() {
        window.orderOut(nil)
        window.ignoresMouseEvents = true
    }

    func tearDown() {
        window.orderOut(nil)
        window.contentView = nil
    }
}

final class RegionPickerView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTracking()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTracking()
    }

    private func updateTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        if let start = startPoint, let current = currentPoint {
            let rect = GeometryMath.normalizedRect(start, current)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            rect.fill()
            NSGraphicsContext.restoreGraphicsState()

            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            NSColor(xshotHex: XShotTheme.accentHex).setStroke()
            border.lineWidth = 2
            border.stroke()

            let label = "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let size = label.size(withAttributes: attrs)
            let hud = CGRect(
                x: rect.midX - size.width / 2 - 8,
                y: max(8, rect.minY - size.height - 16),
                width: size.width + 16,
                height: size.height + 8
            )
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: hud, xRadius: 6, yRadius: 6).fill()
            label.draw(at: CGPoint(x: hud.minX + 8, y: hud.minY + 4), withAttributes: attrs)
        } else if let current = currentPoint {
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let v = NSBezierPath()
            v.move(to: CGPoint(x: current.x, y: bounds.minY))
            v.line(to: CGPoint(x: current.x, y: bounds.maxY))
            v.lineWidth = 1
            v.stroke()
            let h = NSBezierPath()
            h.move(to: CGPoint(x: bounds.minX, y: current.y))
            h.line(to: CGPoint(x: bounds.maxX, y: current.y))
            h.lineWidth = 1
            h.stroke()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        startPoint = p
        currentPoint = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let start = startPoint, let current = currentPoint else { return }
        let rect = GeometryMath.normalizedRect(start, current)
        startPoint = nil
        currentPoint = nil
        if rect.width >= 4 && rect.height >= 4 {
            onSelect?(rect)
        } else {
            onCancel?()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
