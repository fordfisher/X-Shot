import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyHandling, RegionPickerDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeys: HotkeyManager!
    private var picker = RegionPickerController()
    private var capture = ScreenCaptureService()
    private var store: LibraryStore!
    private var libraryModel: LibraryViewModel!
    private var hotkeySettings = HotkeyStore.load()

    private var libraryWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var editorWindows: [UUID: NSWindow] = [:]
    private var captureMenuItem: NSMenuItem?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try LibraryStore(rootURL: try LibraryStore.defaultRoot())
        } catch {
            presentError("Could not open library", error.localizedDescription)
            store = try? LibraryStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("XShot-fallback"))
        }
        libraryModel = LibraryViewModel(store: store!)

        picker.delegate = self
        hotkeys = HotkeyManager(settings: hotkeySettings)
        hotkeys.handler = self
        hotkeys.start()

        setupStatusItem()
        setupMainMenu()
        refreshCaptureMenuTitle()

        if !ScreenCaptureService.hasScreenRecordingPermission() {
            _ = ScreenCaptureService.requestScreenRecordingPermission()
        }
    }

    // MARK: - HotkeyHandling

    public func hotkeyTriggered() {
        beginCapture()
    }

    // MARK: - RegionPickerDelegate

    public func regionPickerDidSelect(_ rect: CGRect) {
        Task { @MainActor in
            await finishCapture(rect: rect)
        }
    }

    public func regionPickerDidCancel() {}

    // MARK: - Actions

    public func beginCapture() {
        if !ScreenCaptureService.hasScreenRecordingPermission() {
            _ = ScreenCaptureService.requestScreenRecordingPermission()
            presentError(
                "Screen Recording required",
                "Enable X-Shot in System Settings → Privacy & Security → Screen Recording, then try again."
            )
            return
        }
        // Status-item menus must finish dismissing before fullscreen overlays appear.
        DispatchQueue.main.async { [weak self] in
            self?.picker.begin()
        }
    }

    public func showLibrary() {
        if let libraryWindow {
            libraryWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            libraryModel.reload()
            return
        }
        let root = LibraryView(
            model: libraryModel,
            onOpen: { [weak self] shot in
                self?.openEditor(for: shot)
            },
            onCapture: { [weak self] in
                self?.beginCapture()
            }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(origin: .zero, size: WindowFactory.librarySize)
        let window = WindowFactory.make(
            title: "X-Shot Library",
            size: WindowFactory.librarySize,
            minSize: WindowFactory.libraryMin,
            content: hosting,
            autosaveName: "XShot.Library.v2"
        )
        window.makeKeyAndOrderFront(nil)
        libraryWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let binding = Binding(
            get: { self.hotkeySettings },
            set: { self.hotkeySettings = $0 }
        )
        let root = SettingsView(
            settings: binding,
            hasScreenPermission: ScreenCaptureService.hasScreenRecordingPermission(),
            onRequestPermission: {
                _ = ScreenCaptureService.requestScreenRecordingPermission()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            },
            onApplyHotkeys: { [weak self] in
                guard let self else { return }
                HotkeyStore.save(self.hotkeySettings)
                self.hotkeys.apply(self.hotkeySettings)
                self.refreshCaptureMenuTitle()
            }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(origin: .zero, size: NSSize(width: 480, height: 460))
        let window = WindowFactory.make(
            title: "X-Shot Settings",
            size: NSSize(width: 480, height: 460),
            minSize: NSSize(width: 420, height: 380),
            content: hosting,
            autosaveName: "XShot.Settings.v2"
        )
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Capture pipeline

    /// Automated capture path (no interactive picker) for crash/regression checks.
    public func selfTestCapture() async {
        guard let screen = NSScreen.main else {
            FileHandle.standardError.write(Data("self-test-capture: no screen\n".utf8))
            NSApp.terminate(nil)
            return
        }
        let frame = screen.frame
        let rect = CGRect(x: frame.midX - 80, y: frame.midY - 60, width: 160, height: 120)
        // Simulate picker hide → capture → editor without interactive UI.
        await finishCapture(rect: rect)
        FileHandle.standardError.write(Data("capture-ok\n".utf8))
        // Give the editor a moment to present, then quit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    private func finishCapture(rect: CGRect) async {
        // Give Core Animation a beat to remove picker windows from the display.
        try? await Task.sleep(nanoseconds: 50_000_000)
        do {
            let image = try await capture.capture(rect: rect)
            guard let png = ScreenCaptureService.pngData(from: image) else {
                presentError("Capture failed", "Could not encode PNG")
                return
            }
            ScreenCaptureService.copyToClipboard(image)

            let shot = Shot(
                width: Int(image.size.width),
                height: Int(image.size.height)
            )
            try store.insert(shot: shot, imageData: png, originalData: png)
            libraryModel.reload()
            openEditor(image: image, shotID: shot.id, document: AnnotationDocument())
        } catch {
            presentError("Capture failed", error.localizedDescription)
        }
    }

    public func openEditor(for shot: Shot) {
        guard let data = try? store.loadImageData(id: shot.id),
              let image = ScreenCaptureService.image(from: data) else {
            presentError("Open failed", "Could not load image")
            return
        }
        // Prefer original + annotations for editing fidelity
        let base: NSImage
        if let original = try? store.loadOriginalData(id: shot.id),
           let originalImage = ScreenCaptureService.image(from: original) {
            base = originalImage
        } else {
            base = image
        }
        let document = (try? store.loadAnnotations(id: shot.id)) ?? AnnotationDocument()
        openEditor(image: base, shotID: shot.id, document: document)
    }

    private func openEditor(image: NSImage, shotID: UUID, document: AnnotationDocument) {
        if let existing = editorWindows[shotID] {
            WindowFactory.enforce(size: WindowFactory.editorSize, minSize: WindowFactory.editorMin, on: existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let session = EditorSession(shotID: shotID, baseImage: image, document: document)
        let root = EditorView(
            session: session,
            onSave: { [weak self] session in
                self?.save(session: session)
            },
            onClose: { [weak self] in
                self?.editorWindows[shotID]?.close()
                self?.editorWindows[shotID] = nil
            }
        )
        let hosting = NSHostingController(rootView: root)
        let window = WindowFactory.make(
            title: "X-Shot Editor",
            size: WindowFactory.editorSize,
            minSize: WindowFactory.editorMin,
            content: hosting,
            autosaveName: "XShot.Editor.v2"
        )
        // Cascade away from the library so the two don't stack confusingly.
        if let libraryFrame = libraryWindow?.frame {
            var frame = window.frame
            frame.origin.x = libraryFrame.origin.x + 36
            frame.origin.y = max(40, libraryFrame.origin.y - 28)
            window.setFrame(frame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        editorWindows[shotID] = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func save(session: EditorSession) {
        let rendered = session.renderedImage()
        guard let png = ScreenCaptureService.pngData(from: rendered) else {
            presentError("Save failed", "Could not encode PNG")
            return
        }
        do {
            if session.baseReplaced,
               let basePNG = ScreenCaptureService.pngData(from: session.baseImage) {
                try store.writeOriginal(id: session.shotID, data: basePNG)
                session.baseReplaced = false
            }
            try store.updateImage(
                id: session.shotID,
                imageData: png,
                hasAnnotations: !session.document.items.isEmpty,
                document: session.document,
                width: Int(rendered.size.width),
                height: Int(rendered.size.height)
            )
            session.isDirty = false
            libraryModel.refreshShot(id: session.shotID)
            ScreenCaptureService.copyToClipboard(rendered)
        } catch {
            presentError("Save failed", error.localizedDescription)
        }
    }

    // MARK: - Menu / status

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "X-Shot")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture Region", action: #selector(captureMenuAction), keyEquivalent: "")
        captureMenuItem = capture
        menu.addItem(capture)
        menu.addItem(NSMenuItem(title: "Library…", action: #selector(libraryMenuAction), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(settingsMenuAction), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit X-Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for entry in menu.items where entry.action != #selector(NSApplication.terminate(_:)) {
            entry.target = self
        }
        item.menu = menu
        statusItem = item
        refreshCaptureMenuTitle()
    }

    private func refreshCaptureMenuTitle() {
        let label = HotkeyParser.displayName(for: hotkeySettings)
        captureMenuItem?.title = "Capture Region  \(label)"
    }

    private func setupMainMenu() {
        let main = NSMenu()
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About X-Shot", action: nil, keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(settingsMenuAction), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit X-Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenu.items[2].target = self
        appMenuItem.submenu = appMenu

        let captureMenuItem = NSMenuItem()
        main.addItem(captureMenuItem)
        let captureMenu = NSMenu(title: "Capture")
        let captureItem = NSMenuItem(title: "Capture Region", action: #selector(captureMenuAction), keyEquivalent: "4")
        captureItem.keyEquivalentModifierMask = [.shift, .command]
        captureItem.target = self
        captureMenu.addItem(captureItem)
        let libItem = NSMenuItem(title: "Library", action: #selector(libraryMenuAction), keyEquivalent: "l")
        libItem.keyEquivalentModifierMask = [.command]
        libItem.target = self
        captureMenu.addItem(libItem)
        captureMenuItem.submenu = captureMenu

        NSApp.mainMenu = main
    }

    @objc private func captureMenuAction() { beginCapture() }
    @objc private func libraryMenuAction() { showLibrary() }
    @objc private func settingsMenuAction() { showSettings() }

    private func presentError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
