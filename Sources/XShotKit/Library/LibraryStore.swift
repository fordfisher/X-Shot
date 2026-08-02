import AppKit
import Foundation
import SQLite3

public enum LibraryError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case notFound
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let s), .prepareFailed(let s), .stepFailed(let s), .io(let s):
            return s
        case .notFound:
            return "Shot not found"
        }
    }
}

/// Local-only shot library: SQLite index + PNG files on disk.
public final class LibraryStore: @unchecked Sendable {
    public let rootURL: URL
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.xshot.library", qos: .userInitiated)

    public var shotsURL: URL { rootURL.appendingPathComponent("shots", isDirectory: true) }
    public var originalsURL: URL { rootURL.appendingPathComponent("originals", isDirectory: true) }
    public var annotationsURL: URL { rootURL.appendingPathComponent("annotations", isDirectory: true) }

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: shotsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: originalsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: annotationsURL, withIntermediateDirectories: true)
        let dbPath = rootURL.appendingPathComponent("library.sqlite").path
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw LibraryError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try exec("""
            CREATE TABLE IF NOT EXISTS shots (
                id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                has_annotations INTEGER NOT NULL DEFAULT 0,
                title TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS idx_shots_created ON shots(created_at DESC);
            """)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    public static func defaultRoot() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = base.appendingPathComponent("XShot", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    public func imageURL(for id: UUID) -> URL {
        shotsURL.appendingPathComponent("\(id.uuidString).png")
    }

    public func originalURL(for id: UUID) -> URL {
        originalsURL.appendingPathComponent("\(id.uuidString).png")
    }

    public func annotationURL(for id: UUID) -> URL {
        annotationsURL.appendingPathComponent("\(id.uuidString).json")
    }

    public func insert(shot: Shot, imageData: Data, originalData: Data? = nil) throws {
        try queue.sync {
            try imageData.write(to: imageURL(for: shot.id), options: .atomic)
            try (originalData ?? imageData).write(to: originalURL(for: shot.id), options: .atomic)
            try exec(
                """
                INSERT INTO shots (id, created_at, width, height, has_annotations, title)
                VALUES ('\(shot.id.uuidString)', \(shot.createdAt.timeIntervalSince1970),
                        \(shot.width), \(shot.height), \(shot.hasAnnotations ? 1 : 0),
                        '\(escape(shot.title))');
                """
            )
        }
    }

    public func updateImage(id: UUID, imageData: Data, hasAnnotations: Bool, document: AnnotationDocument?, width: Int? = nil, height: Int? = nil) throws {
        try queue.sync {
            try imageData.write(to: imageURL(for: id), options: .atomic)
            var sets = ["has_annotations = \(hasAnnotations ? 1 : 0)"]
            if let width { sets.append("width = \(width)") }
            if let height { sets.append("height = \(height)") }
            try exec(
                """
                UPDATE shots SET \(sets.joined(separator: ", "))
                WHERE id = '\(id.uuidString)';
                """
            )
            let annURL = annotationURL(for: id)
            if let document {
                let data = try JSONEncoder().encode(document)
                try data.write(to: annURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: annURL.path) {
                try FileManager.default.removeItem(at: annURL)
            }
        }
    }

    public func writeOriginal(id: UUID, data: Data) throws {
        try queue.sync {
            try data.write(to: originalURL(for: id), options: .atomic)
        }
    }

    public func loadAnnotations(id: UUID) throws -> AnnotationDocument? {
        try queue.sync {
            let url = annotationURL(for: id)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AnnotationDocument.self, from: data)
        }
    }

    public func delete(id: UUID) throws {
        try queue.sync {
            try? FileManager.default.removeItem(at: imageURL(for: id))
            try? FileManager.default.removeItem(at: originalURL(for: id))
            try? FileManager.default.removeItem(at: annotationURL(for: id))
            try exec("DELETE FROM shots WHERE id = '\(id.uuidString)';")
        }
    }

    public func fetchAll() throws -> [Shot] {
        try queue.sync {
            var statement: OpaquePointer?
            let sql = "SELECT id, created_at, width, height, has_annotations, title FROM shots ORDER BY created_at DESC;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw LibraryError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            var result: [Shot] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let idStr = String(cString: sqlite3_column_text(statement, 0))
                let created = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
                let width = Int(sqlite3_column_int(statement, 2))
                let height = Int(sqlite3_column_int(statement, 3))
                let hasAnn = sqlite3_column_int(statement, 4) != 0
                let title = String(cString: sqlite3_column_text(statement, 5))
                guard let id = UUID(uuidString: idStr) else { continue }
                result.append(Shot(id: id, createdAt: created, width: width, height: height, hasAnnotations: hasAnn, title: title))
            }
            return result
        }
    }

    public func fetch(id: UUID) throws -> Shot {
        try queue.sync {
            var statement: OpaquePointer?
            let sql = "SELECT id, created_at, width, height, has_annotations, title FROM shots WHERE id = ? LIMIT 1;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw LibraryError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            let ns = id.uuidString as NSString
            sqlite3_bind_text(statement, 1, ns.utf8String, -1, nil)
            guard sqlite3_step(statement) == SQLITE_ROW else { throw LibraryError.notFound }
            let created = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let width = Int(sqlite3_column_int(statement, 2))
            let height = Int(sqlite3_column_int(statement, 3))
            let hasAnn = sqlite3_column_int(statement, 4) != 0
            let title = String(cString: sqlite3_column_text(statement, 5))
            return Shot(id: id, createdAt: created, width: width, height: height, hasAnnotations: hasAnn, title: title)
        }
    }

    public func loadImageData(id: UUID) throws -> Data {
        try Data(contentsOf: imageURL(for: id))
    }

    public func loadOriginalData(id: UUID) throws -> Data {
        try Data(contentsOf: originalURL(for: id))
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw LibraryError.stepFailed(message)
        }
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }
}
