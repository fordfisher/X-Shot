import AppKit
import Foundation
import XShotKit

@main
enum SmokeTests {
    static func main() async {
        _ = NSApplication.shared
        var failures = 0
        failures += await run("library round-trip", testLibrary)
        failures += await run("annotations Codable", testAnnotationsCodable)
        failures += await run("bounding box", testBoundingBox)
        failures += await run("hotkey parser", testHotkeyParser)
        failures += await run("color codec", testColorCodec)
        failures += await run("region normalize", testRegionNormalize)
        failures += await run("editor undo/redo", testEditorUndo)
        failures += await run("thumbnail downsample", testThumbnailDownsample)
        failures += await run("move translate", testMoveTranslate)
        failures += await run("blur pixelate", testBlurPixelate)
        failures += await run("tool shortcuts", testToolShortcuts)

        if failures == 0 {
            print("All smoke tests passed.")
            exit(0)
        } else {
            print("FAILED: \(failures) test group(s)")
            exit(1)
        }
    }

    static func run(_ name: String, _ body: () async throws -> Void) async -> Int {
        do {
            try await body()
            print("✓ \(name)")
            return 0
        } catch {
            print("✗ \(name): \(error)")
            return 1
        }
    }

    static func testLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XShotSmoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(rootURL: root)
        let shot = Shot(width: 100, height: 50, title: "hello")
        let image = NSImage(size: NSSize(width: 100, height: 50))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 50).fill()
        image.unlockFocus()
        guard let data = ScreenCaptureService.pngData(from: image) else {
            throw TestError("png encode failed")
        }
        try store.insert(shot: shot, imageData: data)
        let all = try store.fetchAll()
        guard all.count == 1, all[0].id == shot.id, all[0].width == 100 else {
            throw TestError("fetch mismatch")
        }
        try store.delete(id: shot.id)
        guard try store.fetchAll().isEmpty else { throw TestError("delete failed") }
    }

    static func testAnnotationsCodable() throws {
        var doc = AnnotationDocument(nextCalloutNumber: 3)
        doc.items.append(AnnotationItem(
            tool: .pen,
            colorHex: "#0D9488",
            strokeWidth: 4,
            points: [CGPointCodable(x: 1, y: 2), CGPointCodable(x: 3, y: 4)]
        ))
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)
        guard decoded == doc else { throw TestError("codable mismatch") }
    }

    static func testBoundingBox() throws {
        let item = AnnotationItem(
            tool: .rectangle,
            colorHex: "#000000",
            strokeWidth: 2,
            points: [CGPointCodable(x: 10, y: 20), CGPointCodable(x: 40, y: 50)]
        )
        let box = AnnotationRenderer.boundingBox(of: item)
        guard box.origin.x == 10, box.origin.y == 20, box.width == 30, box.height == 30 else {
            throw TestError("bbox \(box)")
        }
    }

    static func testHotkeyParser() throws {
        let s = HotkeySettings(primary: .controlShiftCommand4, alsoF13: true)
        guard HotkeyParser.displayName(for: s) == "⌃⇧⌘4 · F13" else { throw TestError("display") }
        guard HotkeyParser.parseDisplay("⌃⇧⌘4 · F13")?.alsoF13 == true else { throw TestError("parse both") }
        guard HotkeyParser.parseDisplay("F13 only")?.primary == .f13 else { throw TestError("parse f13") }
        guard HotkeyParser.parseDisplay("nonsense") == nil else { throw TestError("parse junk") }
    }

    static func testColorCodec() throws {
        let color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let hex = ColorCodec.hex(from: color)
        guard hex == "#FF0000" else { throw TestError(hex) }
        let back = ColorCodec.color(from: hex)
        guard Int(back.redComponent * 255) == 255 else { throw TestError("red") }
    }

    static func testRegionNormalize() throws {
        let r = GeometryMath.normalizedRect(CGPoint(x: 10, y: 20), CGPoint(x: 5, y: 40))
        guard r.origin.x == 5, r.origin.y == 20, r.width == 5, r.height == 20 else {
            throw TestError("\(r)")
        }
    }

    @MainActor
    static func testEditorUndo() throws {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        let session = EditorSession(shotID: UUID(), baseImage: image)
        session.tool = .arrow
        session.beginStroke(at: CGPoint(x: 0, y: 0))
        session.continueStroke(to: CGPoint(x: 10, y: 10))
        session.endStroke()
        guard session.document.items.count == 1 else { throw TestError("after stroke") }
        session.undo()
        guard session.document.items.isEmpty else { throw TestError("after undo") }
        session.redo()
        guard session.document.items.count == 1 else { throw TestError("after redo") }
    }

    @MainActor
    static func testThumbnailDownsample() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XShotThumb-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(rootURL: root)
        let wide = NSImage(size: NSSize(width: 2000, height: 400))
        wide.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 2000, height: 400).fill()
        wide.unlockFocus()
        guard let data = ScreenCaptureService.pngData(from: wide) else { throw TestError("png") }
        let shot = Shot(width: 2000, height: 400)
        try store.insert(shot: shot, imageData: data)
        let model = LibraryViewModel(store: store)
        guard let thumb = model.thumbnail(for: shot) else { throw TestError("no thumb") }
        guard thumb.size.width <= 480, thumb.size.height <= 480 else {
            throw TestError("thumb too large \(thumb.size)")
        }
    }

    static func testMoveTranslate() throws {
        let item = AnnotationItem(
            tool: .arrow,
            colorHex: "#FF0000",
            strokeWidth: 3,
            points: [CGPointCodable(x: 10, y: 10), CGPointCodable(x: 40, y: 40)]
        )
        let moved = AnnotationRenderer.translated(item, by: CGPoint(x: 5, y: -3))
        guard moved.start.x == 15, moved.start.y == 7, moved.end.x == 45, moved.end.y == 37 else {
            throw TestError("translate \(moved.points)")
        }
        guard AnnotationRenderer.hitTest(item: item, at: CGPoint(x: 25, y: 25), tolerance: 8) else {
            throw TestError("hit miss")
        }
    }

    static func testBlurPixelate() throws {
        let image = NSImage(size: NSSize(width: 100, height: 80))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 50, height: 80).fill()
        NSColor.blue.setFill()
        NSRect(x: 50, y: 0, width: 50, height: 80).fill()
        image.unlockFocus()
        guard let out = AnnotationRenderer.pixelate(
            base: image,
            rect: CGRect(x: 10, y: 10, width: 40, height: 30),
            blockSize: 8
        ) else { throw TestError("pixelate nil") }
        guard abs(out.size.width - 40) < 1, abs(out.size.height - 30) < 1 else {
            throw TestError("size \(out.size)")
        }
    }

    static func testToolShortcuts() throws {
        let map: [(Character, AnnotationTool)] = [
            ("m", .move), ("a", .arrow), ("s", .rectangle), ("e", .ellipse),
            ("p", .pen), ("h", .highlighter), ("t", .text), ("c", .callout),
            ("b", .blur), ("r", .crop),
        ]
        for (key, tool) in map {
            guard AnnotationTool.fromShortcutKey(key) == tool else {
                throw TestError("shortcut \(key)")
            }
            guard tool.shortcutKey == key else {
                throw TestError("roundtrip \(tool)")
            }
        }
        guard AnnotationTool.fromShortcutKey("z") == nil else { throw TestError("z") }
    }
}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
