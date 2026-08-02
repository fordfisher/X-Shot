import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum CaptureError: Error, LocalizedError {
    case noDisplay
    case permissionDenied
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available"
        case .permissionDenied: return "Screen Recording permission is required"
        case .failed(let s): return s
        }
    }
}

public final class ScreenCaptureService {
    public init() {}

    /// Captures a rect in global Quartz screen coordinates (origin bottom-left).
    public func capture(rect: CGRect) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { CGRect(x: $0.frame.origin.x, y: $0.frame.origin.y, width: CGFloat($0.width), height: CGFloat($0.height)).intersects(rect) })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = NSScreen.screens.first(where: {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == display.displayID
        })?.backingScaleFactor ?? 2.0

        // Convert global rect into display-local top-left based filter coords.
        let displayBounds = CGDisplayBounds(display.displayID)
        let localX = rect.origin.x - displayBounds.origin.x
        let localYFromBottom = rect.origin.y - displayBounds.origin.y
        // SCStreamConfiguration sourceRect uses top-left origin relative to display.
        let localYTop = displayBounds.height - localYFromBottom - rect.height

        config.sourceRect = CGRect(x: localX, y: localYTop, width: rect.width, height: rect.height)
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: NSSize(width: rect.width, height: rect.height))
    }

    public static func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    public static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
    }

    public static func image(from pngData: Data) -> NSImage? {
        NSImage(data: pngData)
    }

    public static func hasScreenRecordingPermission() -> Bool {
        // Trigger permission prompt by attempting a tiny capture probe if needed.
        CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
