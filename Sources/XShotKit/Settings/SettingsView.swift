import SwiftUI

public struct SettingsView: View {
    @Binding var settings: HotkeySettings
    var hasScreenPermission: Bool
    var onRequestPermission: () -> Void
    var onApplyHotkeys: () -> Void

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
            Section("Capture") {
                Toggle("Also listen for F13 (Print Screen)", isOn: $settings.alsoF13)
                    .onChange(of: settings.alsoF13) { _, _ in onApplyHotkeys() }
                LabeledContent("Primary hotkey", value: HotkeyChord.controlShiftCommand4.displayName)
                Text("Active: \(HotkeyParser.displayName(for: settings))")
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
        .frame(width: 420, height: 320)
    }
}
