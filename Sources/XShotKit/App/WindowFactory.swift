import AppKit

enum WindowFactory {
    static func make(
        title: String,
        size: NSSize,
        minSize: NSSize,
        content: NSViewController,
        autosaveName: String? = nil
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = content
        content.view.translatesAutoresizingMaskIntoConstraints = true
        content.view.autoresizingMask = [.width, .height]
        content.view.frame = NSRect(origin: .zero, size: size)

        window.contentMinSize = minSize
        window.minSize = NSSize(width: minSize.width, height: minSize.height + 28)

        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }

        enforce(size: size, minSize: minSize, on: window)
        window.center()
        window.isReleasedWhenClosed = false

        // Autosave / SwiftUI can still shrink after first layout — re-assert once.
        DispatchQueue.main.async {
            enforce(size: size, minSize: minSize, on: window)
        }
        return window
    }

    static func enforce(size: NSSize, minSize: NSSize, on window: NSWindow) {
        var frame = window.frame
        let chrome = max(0, window.frame.height - window.contentLayoutRect.height)
        var changed = false
        if frame.width < minSize.width {
            frame.size.width = size.width
            changed = true
        }
        if frame.height < minSize.height + chrome {
            frame.size.height = size.height + chrome
            changed = true
        }
        if changed {
            window.setFrame(frame, display: true)
        }
        let contentHeight = max(window.contentLayoutRect.height, minSize.height)
        let contentWidth = max(window.contentLayoutRect.width, minSize.width)
        window.setContentSize(NSSize(width: contentWidth, height: contentHeight))
    }

    static var librarySize: NSSize {
        fitted(ideal: NSSize(width: 1180, height: 780), floor: libraryMin, margin: 80)
    }

    static var libraryMin: NSSize { NSSize(width: 820, height: 560) }

    static var editorSize: NSSize {
        fitted(ideal: NSSize(width: 1280, height: 860), floor: editorMin, margin: 60)
    }

    static var editorMin: NSSize { NSSize(width: 900, height: 600) }

    static var settingsSize: NSSize { NSSize(width: 460, height: 380) }

    private static func fitted(ideal: NSSize, floor: NSSize, margin: CGFloat) -> NSSize {
        guard let screen = NSScreen.main else { return ideal }
        let visible = screen.visibleFrame
        return NSSize(
            width: min(ideal.width, max(floor.width, visible.width - margin)),
            height: min(ideal.height, max(floor.height, visible.height - margin))
        )
    }
}
