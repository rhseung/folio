import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import GRDB
import PDFKit
import Synchronization

public final class SearchStore: Sendable {
    let db: DatabaseQueue

    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try DatabaseQueue(path: url.path)
        } else {
            db = try DatabaseQueue()
        }

        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = true
        migrator.registerMigration("v1") { db in
            // trigram tokenizer는 낱말 안에서도 찾는다. 기본 tokenizer는 공백에서만 나누므로 `매칭`으로 `최대매칭은`을
            // 찾지 못한다.
            try db.execute(
                sql: "CREATE VIRTUAL TABLE item USING fts5(kind UNINDEXED, course UNINDEXED, id UNINDEXED, title, body, tokenize='trigram')"
            )
            try db.execute(sql: "CREATE TABLE course (id TEXT PRIMARY KEY, root TEXT NOT NULL, signature TEXT NOT NULL)")
            try db.execute(sql: "CREATE TABLE pdf (path TEXT PRIMARY KEY, signature TEXT NOT NULL, text TEXT NOT NULL)")
        }
        // 시험이 색인에 들어왔으므로 비워서 모든 과목을 다시 읽고, PDF는 캐시에서 읽는다. `refresh`는 지운 과목의
        // 항목을 `course`로 찾으므로, 그사이 사라진 과목의 항목도 지워지도록 항목도 함께 비운다.
        migrator.registerMigration("v2-exams") { db in
            try db.execute(sql: "DELETE FROM course")
            try db.execute(sql: "DELETE FROM item")
        }
        migrator.registerMigration("v3-session-days") { db in
            try db.execute(sql: "DELETE FROM course")
            try db.execute(sql: "DELETE FROM item")
        }
        migrator.registerMigration("v4-session-units") { db in
            try db.execute(sql: "DELETE FROM course")
            try db.execute(sql: "DELETE FROM item")
        }
        try migrator.migrate(db)
    }

    private static let opened = Mutex<[URL: SearchStore]>([:])

    // iCloud가 동기화하지 않도록 GIST 폴더 밖에 둔다. 두 연결이 한 데이터베이스에 쓰면 서로의 잠금을 기다리므로,
    // 파일마다 하나만 두고 검색 팔레트와 노트 편집기가 함께 쓴다.
    public static func local(for gist: GISTStore, in folder: URL = URL.cachesDirectory) throws -> SearchStore {
        let name = Data(gist.url.standardizedFileURL.path.utf8).base64EncodedString().filter(\.isLetter).suffix(40)
        let url = folder.appending(path: "Folio/search-\(name).sqlite")
        return try opened.withLock { open in
            if let store = open[url] { return store }
            let store = try SearchStore(url: url)
            open[url] = store
            return store
        }
    }

    @discardableResult
    public func refresh(_ gist: GISTStore, progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) throws -> Int {
        let stores = try gist.courseStores()
        let known = try db.read { db in
            try Dictionary(
                Row.fetchAll(db, sql: "SELECT id, root, signature FROM course").map {
                    ($0["root"] as String, ($0["id"] as String, $0["signature"] as String))
                }
            ) { a, _ in a }
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
        for (i, item) in items.enumerated() where item.kind == .material && MaterialFormat(path: item.body) == .pdf {
            items[i].body += "\n" + (try pdfText(store.url.appending(path: item.body)))
        }

        let course = file.course.id.uuidString
        try db.write { db in
            try db.execute(sql: "DELETE FROM item WHERE course = ?", arguments: [course])
            try db.execute(sql: "DELETE FROM course WHERE id = ? OR root = ?", arguments: [course, store.url.path])
            for item in items {
                try db.execute(
                    sql: "INSERT INTO item (kind, course, id, title, body) VALUES (?, ?, ?, ?, ?)",
                    arguments: [item.kind.rawValue, course, item.id.uuidString, item.title, item.body])
            }
            try db.execute(
                sql: "INSERT INTO course (id, root, signature) VALUES (?, ?, ?)", arguments: [course, store.url.path, signature])
        }
    }

    func pdfText(_ url: URL) throws -> String {
        let signature = Self.stamp(url)
        if let text = try db.read({
            try String.fetchOne($0, sql: "SELECT text FROM pdf WHERE path = ? AND signature = ?", arguments: [url.path, signature])
        }) {
            return text
        }
        guard let document = PDFDocument(url: url) else { return "" }
        let text = (document.string ?? "").precomposedStringWithCanonicalMapping
        try db.write {
            try $0.execute(
                sql: "INSERT OR REPLACE INTO pdf (path, signature, text) VALUES (?, ?, ?)", arguments: [url.path, signature, text])
        }
        return text
    }

    static func signature(_ store: CourseStore, _ file: CourseFile) -> String {
        var parts = [stamp(store.courseFileURL)]
        if let files = FileManager.default.enumerator(
            at: store.url.appending(path: CourseFolder.notes.rawValue),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        {
            for case let url as URL in files { parts.append(url.lastPathComponent + stamp(url)) }
        }
        for m in file.materials where m.isPDF { parts.append(stamp(store.url.appending(path: m.path))) }
        for u in file.units { parts.append(u.id.uuidString + stamp(store.quizURL(unit: u.id))) }
        return parts.sorted().joined(separator: "|")
    }

    static func stamp(_ url: URL) -> String {
        guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return "-" }
        return "\(v.contentModificationDate?.timeIntervalSince1970 ?? 0):\(v.fileSize ?? 0)"
    }

    public func items(courses: Set<UUID>, kinds: Set<SearchKind>, limit: Int = 60) throws -> [SearchItem] {
        guard !courses.isEmpty, !kinds.isEmpty else { return [] }
        let sql =
            "SELECT kind, course, id, title FROM item WHERE course IN (\(courses.map { _ in "?" }.joined(separator: ",")))"
            + " AND kind IN (\(kinds.map { _ in "?" }.joined(separator: ","))) ORDER BY title LIMIT ?"
        let args: [any DatabaseValueConvertible] = courses.map(\.uuidString) + kinds.map(\.rawValue) + [limit]
        let rows = try db.read { try Row.fetchAll($0, sql: sql, arguments: StatementArguments(args)) }
        return rows.compactMap { row in
            guard let kind = SearchKind(rawValue: row["kind"]), let course = UUID(uuidString: row["course"]),
                let id = UUID(uuidString: row["id"])
            else { return nil }
            return SearchItem(kind: kind, courseId: course, id: id, title: row["title"])
        }
    }

    public func search(_ query: String, kinds: Set<SearchKind>? = nil, courses: Set<UUID>? = nil, limit: Int = 60) throws -> [SearchHit] {
        let words = query.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var clauses: [String] = [], args: [any DatabaseValueConvertible] = []
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
        if let courses {
            clauses.append("course IN (\(courses.map { _ in "?" }.joined(separator: ",")))"); args += courses.map(\.uuidString)
        }

        let at = "COALESCE(" + words.map { _ in "NULLIF(instr(lower(body), lower(?)), 0)" }.joined(separator: ", ") + ", 1)"
        let sql =
            "SELECT kind, course, id, title, substr(body, max(1, \(at) - 60), 240) AS excerpt FROM item WHERE "
            + clauses.joined(separator: " AND ")
        let rows = try db.read { try Row.fetchAll($0, sql: sql, arguments: StatementArguments(words + args)) }
        let items = rows.compactMap { row -> SearchItem? in
            guard let kind = SearchKind(rawValue: row["kind"]), let course = UUID(uuidString: row["course"]),
                let id = UUID(uuidString: row["id"])
            else { return nil }
            return SearchItem(kind: kind, courseId: course, id: id, title: row["title"], body: row["excerpt"])
        }
        return SearchIndex(items).search(query, limit: limit)
    }
}
