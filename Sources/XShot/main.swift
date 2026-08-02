import AppKit
import XShotKit

enum AppOwner {
    static var delegate: AppDelegate?
}

@main
enum XShotMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppOwner.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)

        if CommandLine.arguments.contains("--self-test-picker") {
            DispatchQueue.main.async {
                delegate.beginCapture()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    FileHandle.standardError.write(Data("picker-ok\n".utf8))
                    app.terminate(nil)
                }
            }
        }

        if CommandLine.arguments.contains("--self-test-capture") {
            DispatchQueue.main.async {
                Task { @MainActor in
                    await delegate.selfTestCapture()
                }
            }
        }

        app.run()
    }
}
