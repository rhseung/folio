import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import GRDB
import PDFKit

/// The per-device search index (docs/SPEC.md "검색"): a cache in local SQLite, rebuilt from the course folders whenever
/// they change, never written back to them.
public final class SearchStore: Sendable {
    let db: DatabaseQueue

    /// `url` nil keeps the index in memory.
    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try DatabaseQueue(path: url.path)
        } else {
            db = try DatabaseQueue()
        }
        var migrator = DatabaseMigrator()
        // A cache can always be rebuilt, so a schema change drops it instead of migrating.
        migrator.eraseDatabaseOnSchemaChange = true
        migrator.registerMigration("v1") { db in
            // The trigram tokenizer matches inside words; the default one splits on spaces only, so `매칭` would miss `최대매칭은`.
            try db.execute(sql: "CREATE VIRTUAL TABLE item USING fts5(kind UNINDEXED, course UNINDEXED, id UNINDEXED, title, body, tokenize='trigram')")
            try db.execute(sql: "CREATE TABLE course (id TEXT PRIMARY KEY, root TEXT NOT NULL, signature TEXT NOT NULL)")
            // Text pulled out of a PDF, kept apart so editing course.json doesn't read every textbook again.
            try db.execute(sql: "CREATE TABLE pdf (path TEXT PRIMARY KEY, signature TEXT NOT NULL, text TEXT NOT NULL)")
        }
        try migrator.migrate(db)
    }

    /// The app's index for this device, outside the GIST folder so iCloud never syncs it.
    public static func local(for gist: GISTStore, in folder: URL = URL.cachesDirectory) throws -> SearchStore {
        let name = Data(gist.url.standardizedFileURL.path.utf8).base64EncodedString().filter(\.isLetter).suffix(40)
        return try SearchStore(url: folder.appending(path: "Folio/search-\(name).sqlite"))
    }

    /// Reads again the courses whose course.json, notes, or tracked PDFs changed since last time, and drops courses that
    /// are gone. Returns how many courses it read. `progress` gets (read so far, to read) before each course and once at
    /// the end, so a first build (minutes, with textbooks) can show how far it is.
    @discardableResult
    public func refresh(_ gist: GISTStore, progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) throws -> Int {
        let stores = try gist.courseStores()
        let known = try db.read { db in
            try Dictionary(Row.fetchAll(db, sql: "SELECT id, root, signature FROM course").map { ($0["root"] as String, ($0["id"] as String, $0["signature"] as String)) }) { a, _ in a }
        }
        var stale: [(CourseStore, CourseFile, String)] = []
        var seen: Set<String> = []
        for store in stores {
            seen.insert(store.url.path)
            guard let file = try? store.load().model else { continue }
            let signature = Self.signature(store, file)
            if let (id, old) = known[store.url.path], old == signature, id == file.course.id.uuidString { continue }
            stale.append((store, file, signature))
        }
        try db.write { db in
            for (root, (id, _)) in known where !seen.contains(root) {
                try db.execute(sql: "DELETE FROM item WHERE course = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM course WHERE root = ?", arguments: [root])
            }
        }
        for (i, (store, file, signature)) in stale.enumerated() {
            progress?(i, stale.count)
            try index(store, file, signature: signature)
        }
        if !stale.isEmpty { progress?(stale.count, stale.count) }
        return stale.count
    }

    func index(_ store: CourseStore, _ file: CourseFile, signature: String) throws {
        let notes = ((try? store.notes()) ?? []).compactMap { note in
            note.meta.id.map { (id: $0, title: note.title, body: Frontmatter.split((try? store.read(note)) ?? "").body) }
        }
        let cards = file.units.flatMap { (try? store.loadQuiz(unit: $0.id).model.cards) ?? [] }
        var items = SearchIndex.items(for: file, notes: notes, cards: cards)
        for (i, item) in items.enumerated() where item.kind == .material && item.body.lowercased().hasSuffix(".pdf") {
            items[i].body += "\n" + (try pdfText(store.url.appending(path: item.body)))
        }
        let course = file.course.id.uuidString
        try db.write { db in
            try db.execute(sql: "DELETE FROM item WHERE course = ?", arguments: [course])
            try db.execute(sql: "DELETE FROM course WHERE id = ? OR root = ?", arguments: [course, store.url.path])
            for item in items {
                try db.execute(sql: "INSERT INTO item (kind, course, id, title, body) VALUES (?, ?, ?, ?, ?)",
                               arguments: [item.kind.rawValue, course, item.id.uuidString, item.title, item.body])
            }
            try db.execute(sql: "INSERT INTO course (id, root, signature) VALUES (?, ?, ?)", arguments: [course, store.url.path, signature])
        }
    }

    func pdfText(_ url: URL) throws -> String {
        let signature = Self.stamp(url)
        if let text = try db.read({ try String.fetchOne($0, sql: "SELECT text FROM pdf WHERE path = ? AND signature = ?", arguments: [url.path, signature]) }) {
            return text
        }
        // A file still in iCloud (or unreadable) has no text yet; its stamp changes once it downloads, which reads it again.
        guard let document = PDFDocument(url: url) else { return "" }
        let text = (document.string ?? "").precomposedStringWithCanonicalMapping
        try db.write { try $0.execute(sql: "INSERT OR REPLACE INTO pdf (path, signature, text) VALUES (?, ?, ?)", arguments: [url.path, signature, text]) }
        return text
    }

    /// What changes when anything the index reads from this course changes: course.json, any file under Notes/, a unit's
    /// quiz file, a tracked PDF.
    static func signature(_ store: CourseStore, _ file: CourseFile) -> String {
        var parts = [stamp(store.courseFileURL)]
        if let files = FileManager.default.enumerator(at: store.url.appending(path: CourseFolder.notes.rawValue), includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) {
            for case let url as URL in files { parts.append(url.lastPathComponent + stamp(url)) }
        }
        for m in file.materials where m.path.lowercased().hasSuffix(".pdf") { parts.append(stamp(store.url.appending(path: m.path))) }
        for u in file.units { parts.append(u.id.uuidString + stamp(store.quizURL(unit: u.id))) }
        return parts.sorted().joined(separator: "|")
    }

    static func stamp(_ url: URL) -> String {
        guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return "-" }
        return "\(v.contentModificationDate?.timeIntervalSince1970 ?? 0):\(v.fileSize ?? 0)"
    }

    /// Every word must appear in the title or body; ranking and snippets are `SearchIndex`'s, run on the rows that match.
    public func search(_ query: String, kinds: Set<SearchKind>? = nil, courses: Set<UUID>? = nil, limit: Int = 60) throws -> [SearchHit] {
        let words = query.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var clauses: [String] = [], args: [any DatabaseValueConvertible] = []
        // Trigrams index words of three or more characters; shorter ones (most Korean words) are found by scanning.
        let long = words.filter { $0.count >= 3 }
        if !long.isEmpty {
            clauses.append("item MATCH ?")
            args.append(long.map { "\"" + $0.replacing("\"", with: "\"\"") + "\"" }.joined(separator: " AND "))
        }
        for word in words where word.count < 3 {
            let like = "%" + word.replacing("\\", with: "\\\\").replacing("%", with: "\\%").replacing("_", with: "\\_") + "%"
            clauses.append("(title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\')")
            args += [like, like]
        }
        if let kinds { clauses.append("kind IN (\(kinds.map { _ in "?" }.joined(separator: ",")))"); args += kinds.map(\.rawValue) }
        if let courses { clauses.append("course IN (\(courses.map { _ in "?" }.joined(separator: ",")))"); args += courses.map(\.uuidString) }
        // Only the text around the first word that is in the body comes back, so a textbook's body isn't read whole per hit.
        let at = "COALESCE(" + words.map { _ in "NULLIF(instr(lower(body), lower(?)), 0)" }.joined(separator: ", ") + ", 1)"
        let sql = "SELECT kind, course, id, title, substr(body, max(1, \(at) - 60), 240) AS excerpt FROM item WHERE " + clauses.joined(separator: " AND ")
        let rows = try db.read { try Row.fetchAll($0, sql: sql, arguments: StatementArguments(words + args)) }
        let items = rows.compactMap { row -> SearchItem? in
            guard let kind = SearchKind(rawValue: row["kind"]), let course = UUID(uuidString: row["course"]), let id = UUID(uuidString: row["id"]) else { return nil }
            return SearchItem(kind: kind, courseId: course, id: id, title: row["title"], body: row["excerpt"])
        }
        return SearchIndex(items).search(query, limit: limit)
    }
}
