import AppKit
import SwiftUI

public struct SettingsView: View {
    @Binding var settings: HotkeySettings
    var hasScreenPermission: Bool
    var onRequestPermission: () -> Void
    var onApplyHotkeys: () -> Void

    @State private var isRecording = false

    public init(
        settings: Binding<HotkeySettings>,
        hasScreenPermission: Bool,
        onRequestPermission: @escaping () -> Void,
        onApplyHotkeys: @escaping () -> Void
    ) {
        self._settings = settings
        self.hasScreenPermission = hasScreenPermission
        self.onRequestPermission = onRequestPermission
        self.onApplyHotkeys = onApplyHotkeys
    }

    public var body: some View {
        Form {
            Section("Capture hotkey") {
                Picker("Shortcut", selection: $settings.preset) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: settings.preset) { _, newValue in
                    if newValue != .custom {
                        isRecording = false
                    }
                    onApplyHotkeys()
                }

                if settings.preset == .custom {
                    HStack {
                        Text("Custom")
                        Spacer()
                        Text(settings.custom.displayName)
                            .foregroundStyle(.secondary)
                            .monospaced()
                        Button(isRecording ? "Listening…" : "Record…") {
                            isRecording.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    if isRecording {
                        ShortcutRecorderRepresentable { binding in
                            settings.custom = binding
                            settings.preset = .custom
                            isRecording = false
                            onApplyHotkeys()
                        }
                        .frame(height: 1)
                        .opacity(0)
                        Text("Press the new shortcut now (include ⌘ / ⌥ / ⌃ / ⇧). Esc cancels.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Also listen for F13 (Print Screen)", isOn: $settings.alsoF13)
                    .onChange(of: settings.alsoF13) { _, _ in onApplyHotkeys() }
                    .disabled(settings.preset == .f13)

                LabeledContent("Active") {
                    Text(HotkeyParser.displayName(for: settings))
                        .monospaced()
                }

                Text("Turn off the same combo under System Settings → Keyboard → Keyboard Shortcuts → Screenshots if macOS still owns it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    Text(hasScreenPermission ? "Granted" : "Required")
                        .foregroundStyle(hasScreenPermission ? .green : .orange)
                }
                if !hasScreenPermission {
                    Button("Request Screen Recording…", action: onRequestPermission)
                }
            }
            Section("About") {
                Text("X-Shot keeps everything on this Mac — no cloud, no accounts.")
                    .foregroundStyle(.secondary)
                LabeledContent("Library", value: "~/Library/Application Support/XShot")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 460, minHeight: 420)
    }
}

/// Invisible helper that steals the next key-down and turns it into a HotkeyBinding.
struct ShortcutRecorderRepresentable: NSViewRepresentable {
    var onRecorded: (HotkeyBinding) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onRecorded = onRecorded
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.onRecorded = onRecorded
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class ShortcutRecorderView: NSView {
    var onRecorded: ((HotkeyBinding) -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startMonitor()
    }

    deinit {
        stopMonitor()
    }

    private func startMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape cancels
                self.stopMonitor()
                return nil
            }
            if let binding = HotkeyBinding.from(event: event) {
                self.onRecorded?(binding)
                self.stopMonitor()
                return nil
            }
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return }
        if let binding = HotkeyBinding.from(event: event) {
            onRecorded?(binding)
        }
    }
}
