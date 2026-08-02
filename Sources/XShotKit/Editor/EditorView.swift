import AppKit
import SwiftUI

public struct EditorView: View {
    @ObservedObject var session: EditorSession
    var onSave: (EditorSession) -> Void
    var onClose: () -> Void

    @State private var saveFlash = false

    public init(session: EditorSession, onSave: @escaping (EditorSession) -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            AnnotationCanvasView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 480)
            footer
        }
        .background(Color(nsColor: NSColor(xshotHex: XShotTheme.chromeHex)))
        .frame(minWidth: 900, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress { press in
            // Don't fight ⌘C / ⌘S / etc., or steal keys from focused text fields.
            if !press.modifiers.isEmpty { return .ignored }
            guard let ch = press.characters.lowercased().first,
                  let tool = AnnotationTool.fromShortcutKey(ch) else {
                return .ignored
            }
            session.selectTool(tool)
            return .handled
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
            if session.tool == .crop, session.draft?.tool == .crop {
                Button("Apply Crop") {
                    _ = session.applyCrop()
                }
                .buttonStyle(.bordered)
            }
            Divider().frame(height: 22)

            if session.tool != .move && session.tool != .crop && session.tool != .blur {
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: ColorCodec.color(from: session.colorHex)) },
                    set: { session.colorHex = ColorCodec.hex(from: NSColor($0)) }
                ))
                .labelsHidden()
                .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 0) {
                Slider(value: $session.strokeWidth, in: 1...12)
                    .frame(width: 110)
                Text(sliderLabel)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))
            }

            Divider().frame(height: 22)

            Button {
                session.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!session.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo ⌘Z")

            Button {
                session.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!session.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo ⌘⇧Z")

            Button {
                session.deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(session.selectedID == nil)
            .help("Delete selected (⌫)")

            Spacer()

            Button("Copy") {
                session.copyToClipboard()
            }
            .keyboardShortcut("c", modifiers: .command)
            .help("⌘C")

            Button(saveFlash ? "Saved" : "Save") {
                onSave(session)
                withAnimation { saveFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    saveFlash = false
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: NSColor(xshotHex: XShotTheme.accentHex)))
            .help("⌘S")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: NSColor(xshotHex: XShotTheme.chromeHex)))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: NSColor(xshotHex: XShotTheme.borderHex)))
                .frame(height: 1)
        }
    }

    private var sliderLabel: String {
        switch session.tool {
        case .blur: return "Blur strength"
        case .text: return "Text size"
        case .move, .crop: return " "
        default: return "Stroke"
        }
    }

    private var footer: some View {
        HStack {
            Text(session.isDirty ? "Unsaved annotations" : "Ready")
                .font(.caption)
                .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))
            Spacer()
            Text(footerHint)
                .font(.caption)
                .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footerHint: String {
        switch session.tool {
        case .move:
            return "M move · drag to reposition · ⌫ delete · shortcuts: A S E P H T C B R"
        case .text:
            return "T text · click to type (shortcuts pause while typing) · ⌘C / ⌘S"
        case .blur:
            return "B blur · drag to redact · R crop · M move"
        case .crop:
            return "R crop · drag region, then Apply Crop"
        default:
            return "Keys: M A S E P H T C B R · ⌘C copy · ⌘S save · Esc close"
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let selected = session.tool == tool
        return Button {
            session.tool = tool
        } label: {
            Image(systemName: icon(for: tool))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color(nsColor: NSColor(xshotHex: XShotTheme.accentSoftHex)) : .clear)
                )
                .foregroundStyle(
                    selected
                        ? Color(nsColor: NSColor(xshotHex: XShotTheme.accentHex))
                        : Color(nsColor: NSColor(xshotHex: XShotTheme.textHex))
                )
        }
        .buttonStyle(.plain)
        .help("\(tool.displayName) (\(String(tool.shortcutKey).uppercased()))")
    }

    private func icon(for tool: AnnotationTool) -> String {
        switch tool {
        case .move: return "hand.raised"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .callout: return "1.circle.fill"
        case .blur: return "aqi.medium"
        case .crop: return "crop"
        }
    }
}
