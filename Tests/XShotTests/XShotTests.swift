import XCTest
@testable import XShotKit
import Foundation
import AppKit

final class LibraryStoreTests: XCTestCase {
    func testInsertFetchDeleteRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XShotTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LibraryStore(rootURL: root)
        let shot = Shot(width: 100, height: 50, title: "hello")
        let image = NSImage(size: NSSize(width: 100, height: 50))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 50).fill()
        image.unlockFocus()
        let data = try XCTUnwrap(ScreenCaptureService.pngData(from: image))

        try store.insert(shot: shot, imageData: data)
        let all = try store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, shot.id)
        XCTAssertEqual(all[0].width, 100)

        let loaded = try store.loadImageData(id: shot.id)
        XCTAssertFalse(loaded.isEmpty)

        try store.delete(id: shot.id)
        XCTAssertTrue(try store.fetchAll().isEmpty)
    }

    func testUpdateAnnotations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XShotTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try LibraryStore(rootURL: root)
        let shot = Shot(width: 10, height: 10)
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // not a real png decode needed for store
        // Use minimal valid-enough write — store doesn't validate PNG
        try store.insert(shot: shot, imageData: data)

        var doc = AnnotationDocument()
        doc.items.append(AnnotationItem(
            tool: .arrow,
            colorHex: "#FF0000",
            strokeWidth: 2,
            points: [CGPointCodable(x: 0, y: 0), CGPointCodable(x: 5, y: 5)]
        ))
        try store.updateImage(id: shot.id, imageData: data, hasAnnotations: true, document: doc)

        let fetched = try store.fetch(id: shot.id)
        XCTAssertTrue(fetched.hasAnnotations)
        let loaded = try XCTUnwrap(store.loadAnnotations(id: shot.id))
        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertEqual(loaded.items[0].tool, .arrow)
    }
}

final class HotkeyParserTests: XCTestCase {
    func testDisplayName() {
        let s = HotkeySettings(primary: .controlShiftCommand4, alsoF13: true)
        XCTAssertEqual(HotkeyParser.displayName(for: s), "⌃⇧⌘4 · F13")
    }

    func testParse() {
        XCTAssertEqual(HotkeyParser.parseDisplay("⌃⇧⌘4 · F13")?.alsoF13, true)
        XCTAssertEqual(HotkeyParser.parseDisplay("F13 only")?.primary, .f13)
        XCTAssertNil(HotkeyParser.parseDisplay("nonsense"))
    }
}

final class AnnotationTests: XCTestCase {
    func testCodableRoundTrip() throws {
        var doc = AnnotationDocument(nextCalloutNumber: 3)
        doc.items.append(AnnotationItem(
            tool: .pen,
            colorHex: "#0D9488",
            strokeWidth: 4,
            points: [CGPointCodable(x: 1, y: 2), CGPointCodable(x: 3, y: 4)]
        ))
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)
        XCTAssertEqual(decoded, doc)
    }

    func testBoundingBox() {
        let item = AnnotationItem(
            tool: .rectangle,
            colorHex: "#000000",
            strokeWidth: 2,
            points: [CGPointCodable(x: 10, y: 20), CGPointCodable(x: 40, y: 50)]
        )
        let box = AnnotationRenderer.boundingBox(of: item)
        XCTAssertEqual(box.origin.x, 10)
        XCTAssertEqual(box.origin.y, 20)
        XCTAssertEqual(box.width, 30)
        XCTAssertEqual(box.height, 30)
    }

    @MainActor
    func testEditorUndoRedo() {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        let session = EditorSession(shotID: UUID(), baseImage: image)
        session.tool = .arrow
        session.beginStroke(at: CGPoint(x: 0, y: 0))
        session.continueStroke(to: CGPoint(x: 10, y: 10))
        session.endStroke()
        XCTAssertEqual(session.document.items.count, 1)
        session.undo()
        XCTAssertEqual(session.document.items.count, 0)
        session.redo()
        XCTAssertEqual(session.document.items.count, 1)
    }
}

final class ColorCodecTests: XCTestCase {
    func testHexRoundTrip() {
        let color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let hex = ColorCodec.hex(from: color)
        XCTAssertEqual(hex, "#FF0000")
        let back = ColorCodec.color(from: hex)
        XCTAssertEqual(Int(back.redComponent * 255), 255)
    }
}

final class RegionMathTests: XCTestCase {
    func testNormalizedRect() {
        let r = GeometryMath.normalizedRect(CGPoint(x: 10, y: 20), CGPoint(x: 5, y: 40))
        XCTAssertEqual(r.origin.x, 5)
        XCTAssertEqual(r.origin.y, 20)
        XCTAssertEqual(r.width, 5)
        XCTAssertEqual(r.height, 20)
    }
}
