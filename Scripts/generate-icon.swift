#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22

    // Background — graphite with teal accent wash
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(srgbRed: 0.12, green: 0.14, blue: 0.17, alpha: 1).setFill()
    bg.fill()

    let inset = rect.insetBy(dx: size * 0.08, dy: size * 0.08)
    let accent = NSBezierPath(roundedRect: inset, xRadius: radius * 0.7, yRadius: radius * 0.7)
    NSColor(srgbRed: 0.05, green: 0.58, blue: 0.53, alpha: 0.22).setFill()
    accent.fill()

    // Viewfinder corners
    let stroke = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1)
    stroke.setStroke()
    let m = size * 0.22
    let len = size * 0.16
    let w = max(2, size * 0.045)
    func corner(_ x: CGFloat, _ y: CGFloat, dx: CGFloat, dy: CGFloat) {
        let p = NSBezierPath()
        p.lineWidth = w
        p.lineCapStyle = .round
        p.move(to: NSPoint(x: x + dx * len, y: y))
        p.line(to: NSPoint(x: x, y: y))
        p.line(to: NSPoint(x: x, y: y + dy * len))
        p.stroke()
    }
    corner(m, m, dx: 1, dy: 1)
    corner(size - m, m, dx: -1, dy: 1)
    corner(m, size - m, dx: 1, dy: -1)
    corner(size - m, size - m, dx: -1, dy: -1)

    // Center crosshair / X mark for X-Shot
    let cx = size / 2, cy = size / 2
    let arm = size * 0.12
    let cross = NSBezierPath()
    cross.lineWidth = w
    cross.lineCapStyle = .round
    cross.move(to: NSPoint(x: cx - arm, y: cy - arm))
    cross.line(to: NSPoint(x: cx + arm, y: cy + arm))
    cross.move(to: NSPoint(x: cx + arm, y: cy - arm))
    cross.line(to: NSPoint(x: cx - arm, y: cy + arm))
    NSColor(srgbRed: 0.05, green: 0.58, blue: 0.53, alpha: 1).setStroke()
    cross.stroke()

    // Small shutter circle
    let r = size * 0.055
    let dot = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill()
    dot.fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1)
    }
    try data.write(to: url)
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("diana.k@example.org", 32),
    ("icon_32x32.png", 32),
    ("ivan.p@example.net", 64),
    ("icon_128x128.png", 128),
    ("wendy.h@example.net", 256),
    ("icon_256x256.png", 256),
    ("wendy.h@example.net", 512),
    ("icon_512x512.png", 512),
    ("walt.e@example.net", 1024),
]

for (name, size) in sizes {
    try writePNG(drawIcon(size: size), to: iconset.appendingPathComponent(name))
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
print("Wrote \(icns.path)")
