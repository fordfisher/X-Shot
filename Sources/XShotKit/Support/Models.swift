import CoreGraphics
import Foundation

public struct Shot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var width: Int
    public var height: Int
    public var hasAnnotations: Bool
    public var title: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        width: Int,
        height: Int,
        hasAnnotations: Bool = false,
        title: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.hasAnnotations = hasAnnotations
        self.title = title
    }
}

public enum AnnotationTool: String, CaseIterable, Codable, Sendable {
    case move
    case arrow
    case rectangle
    case ellipse
    case pen
    case highlighter
    case text
    case callout
    case blur
    case crop

    /// Tools that create drawable annotation items.
    public var createsAnnotation: Bool {
        switch self {
        case .move, .crop: return false
        default: return true
        }
    }

    public var displayName: String {
        switch self {
        case .move: return "Move"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .callout: return "Callout"
        case .blur: return "Blur"
        case .crop: return "Crop"
        }
    }

    /// Single-key shortcut while editing (ignored during inline text entry).
    public var shortcutKey: Character {
        switch self {
        case .move: return "m"
        case .arrow: return "a"
        case .rectangle: return "s"
        case .ellipse: return "e"
        case .pen: return "p"
        case .highlighter: return "h"
        case .text: return "t"
        case .callout: return "c"
        case .blur: return "b"
        case .crop: return "r" // region / crop
        }
    }

    public static func fromShortcutKey(_ raw: Character) -> AnnotationTool? {
        let key = Character(raw.lowercased())
        return allCases.first { $0.shortcutKey == key }
    }
}

public struct AnnotationDocument: Codable, Equatable, Sendable {
    public var items: [AnnotationItem]
    public var nextCalloutNumber: Int

    public init(items: [AnnotationItem] = [], nextCalloutNumber: Int = 1) {
        self.items = items
        self.nextCalloutNumber = nextCalloutNumber
    }
}

public struct AnnotationItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var tool: AnnotationTool
    public var colorHex: String
    public var strokeWidth: Double
    public var points: [CGPointCodable]
    public var text: String
    public var calloutNumber: Int?

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        colorHex: String,
        strokeWidth: Double,
        points: [CGPointCodable] = [],
        text: String = "",
        calloutNumber: Int? = nil
    ) {
        self.id = id
        self.tool = tool
        self.colorHex = colorHex
        self.strokeWidth = strokeWidth
        self.points = points
        self.text = text
        self.calloutNumber = calloutNumber
    }

    public var start: CGPoint {
        points.first?.cgPoint ?? .zero
    }

    public var end: CGPoint {
        points.last?.cgPoint ?? start
    }
}

public struct CGPointCodable: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public enum HotkeyChord: Equatable, Sendable {
    case controlShiftCommand4
    case f13

    public var displayName: String {
        switch self {
        case .controlShiftCommand4: return "⌃⇧⌘4"
        case .f13: return "F13"
        }
    }
}

public struct HotkeySettings: Equatable, Sendable {
    public var primary: HotkeyChord
    public var alsoF13: Bool

    public static let `default` = HotkeySettings(primary: .controlShiftCommand4, alsoF13: true)

    public init(primary: HotkeyChord = .controlShiftCommand4, alsoF13: Bool = true) {
        self.primary = primary
        self.alsoF13 = alsoF13
    }
}
