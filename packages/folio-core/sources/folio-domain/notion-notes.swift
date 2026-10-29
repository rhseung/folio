import Foundation

/// One course's lecture notes and score breakdown as dumped from Notion (`<dump>/<page id>/index.json`).
/// IDs are Notion page IDs and are kept as Folio IDs, so importing twice adds nothing new.
public struct NotionCourseDump: Codable, Sendable {
    public struct NoteRow: Codable, Sendable {
        public var id: UUID
        public var title: String
        /// `러프`, `복습` or nil.
        public var kind: String?
        public var date: String?
        /// Body file relative to the dump folder; nil for an empty page.
        public var file: String?
    }

    public struct ScoreRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var weight: Double?
        public var score: Double?
        public var max: Double?
        public var parentId: UUID?
    }

    public struct ImageRow: Codable, Sendable {
        public var source: String
        public var file: String?

        public init(source: String, file: String?) {
            self.source = source
            self.file = file
        }
    }

    public var coursePageId: UUID
    public var title: String
    public var notes: [NoteRow]
    public var scores: [ScoreRow]
    public var images: [ImageRow]

    public init(coursePageId: UUID, title: String, notes: [NoteRow], scores: [ScoreRow], images: [ImageRow]) {
        self.coursePageId = coursePageId
        self.title = title
        self.notes = notes
        self.scores = scores
        self.images = images
    }
}

/// A note to write: its body comes from `sourceFile` in the dump.
public struct NotionNotePlan: Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var meta: NoteMeta
    public var sourceFile: String

    public init(id: UUID, title: String, meta: NoteMeta, sourceFile: String) {
        self.id = id
        self.title = title
        self.meta = meta
        self.sourceFile = sourceFile
    }
}

public struct NotionMergeResult: Sendable {
    public var file: CourseFile
    public var notes: [NotionNotePlan]
    public var sessionsAdded: Int
    public var componentsAdded: Int
    public var scoresAdded: Int
    public var warnings: [String]
}

public enum NotionNotesImporter {
    /// Titles come back with markdown escapes (`1\\. Numbers`) or wrapped in tags (`<p>Worksheet</p>`).
    static func clean(_ title: String) -> String {
        var s = title
        s.replace(/<[^>]+>/) { _ in "" }
        s.replace(/\\([\\`*_{}\[\]()#+\-.!~<>|])/) { m in String(m.1) }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `7주차-2` or `7주차-2 정리`.
    static func session(of title: String) -> (week: Int, index: Int, review: Bool)? {
        guard let m = title.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(\d+)주차-(\d+)(\s*정리)?/) else { return nil }
        return (Int(m.1)!, Int(m.2)!, m.3 != nil)
    }

    /// Adds sessions, note links, grade components and scores from `dump` to `file` without touching what is there.
    /// Notes whose ID is in `existingNotes` are skipped; the caller writes the returned note plans.
    public static func merge(_ dump: NotionCourseDump, into file: CourseFile, existingNotes: Set<UUID>,
                             calendar: Calendar, device: DeviceID, now: Date) -> NotionMergeResult {
        var file = file
        var result = NotionMergeResult(file: file, notes: [], sessionsAdded: 0, componentsAdded: 0, scoresAdded: 0, warnings: [])

        let dump = cleaned(dump)
        for row in dump.notes.sorted(by: { ($0.date ?? "", $0.title) < ($1.date ?? "", $1.title) }) {
            guard let source = row.file else { continue }
            var sessionId: UUID?
            var kind: NoteKind = row.kind == "러프" ? .rough : .topic
            if let s = session(of: row.title) {
                let review = row.kind == "복습" || (row.kind == nil && s.review)
                kind = review ? .review : .rough
                let index: Int
                if let existing = file.sessions.firstIndex(where: { $0.week == s.week && $0.index == s.index }) {
                    index = existing
                } else {
                    let day = row.date.flatMap(LocalDate.init).flatMap { $0.date(in: calendar) } ?? now
                    file.sessions.append(Session(device: device, at: now, week: s.week, index: s.index, date: day))
                    result.sessionsAdded += 1
                    index = file.sessions.count - 1
                }
                if review {
                    if file.sessions[index].reviewNoteId == nil { file.sessions[index].reviewNoteId = row.id }
                } else if file.sessions[index].roughNoteId == nil {
                    file.sessions[index].roughNoteId = row.id
                }
                sessionId = file.sessions[index].id
            }
            if !existingNotes.contains(row.id) {
                result.notes.append(NotionNotePlan(id: row.id, title: row.title, meta: NoteMeta(id: row.id, kind: kind, sessionId: sessionId), sourceFile: source))
            }
        }
        file.sessions.sort { ($0.week, $0.index) < ($1.week, $1.index) }

        mergeScores(dump.scores, into: &file, result: &result, device: device, now: now)
        result.file = file
        return result
    }

    static func cleaned(_ dump: NotionCourseDump) -> NotionCourseDump {
        var d = dump
        for i in d.notes.indices { d.notes[i].title = clean(d.notes[i].title) }
        for i in d.scores.indices { d.scores[i].name = clean(d.scores[i].name) }
        return d
    }

    /// Top-level rows are components; every leaf under one becomes a score of that component.
    /// A top-level row with its own score and no children is scored under its own name.
    static func mergeScores(_ rows: [NotionCourseDump.ScoreRow], into file: inout CourseFile, result: inout NotionMergeResult, device: DeviceID, now: Date) {
        let ids = Set(rows.map(\.id))
        let parent = Dictionary(keepingFirst: rows.compactMap { r in r.parentId.flatMap { ids.contains($0) ? (r.id, $0) : nil } })
        let hasChildren = Set(parent.values)
        func existing(_ row: NotionCourseDump.ScoreRow) -> UUID? {
            file.components.first { $0.id == row.id || $0.name.caseInsensitiveCompare(row.name.trimmingCharacters(in: .whitespaces)) == .orderedSame }?.id
        }
        func ancestors(_ id: UUID) -> [UUID] {
            var chain = [id]
            while let p = parent[chain.last!], !chain.contains(p) { chain.append(p) }
            return chain
        }
        // A row already stored as a component (an earlier import may have stored sub-items) keeps its scores;
        // its parent is then not added on top, which would count the same weight twice.
        let covered = Set(rows.filter { existing($0) != nil }.flatMap { ancestors($0.id).dropFirst() })
        let hadComponents = !file.components.isEmpty

        var componentFor: [UUID: UUID] = [:]
        for row in rows {
            if let id = existing(row) { componentFor[row.id] = id }
        }
        for row in rows where parent[row.id] == nil && componentFor[row.id] == nil && !covered.contains(row.id) {
            let order = (file.components.map(\.order).max() ?? -1) + 1
            file.components.append(GradeComponent(id: row.id, device: device, at: now, name: row.name.trimmingCharacters(in: .whitespaces),
                                                  weight: row.weight ?? 0, order: order))
            componentFor[row.id] = row.id
            result.componentsAdded += 1
        }

        // Some courses give weights as points (summing to 1000); components are percentages.
        let total = file.components.map(\.weight).reduce(0, +)
        if !hadComponents, total > 150 {
            for i in file.components.indices { file.components[i].weight *= 100 / total }
            result.warnings.append("평가 비중 합계가 \(Int(total))이라 100으로 환산함")
        }

        for row in rows where !hasChildren.contains(row.id) {
            guard let score = row.score else { continue }
            guard let componentId = ancestors(row.id).lazy.compactMap({ componentFor[$0] }).first else {
                result.warnings.append("\(row.name): 맞는 평가 항목이 없어 점수를 건너뜀")
                continue
            }
            guard let max = row.max, max > 0 else {
                result.warnings.append("\(row.name): 만점이 없어 점수를 건너뜀")
                continue
            }
            let title = row.name.trimmingCharacters(in: .whitespaces)
            let duplicate = file.scores.contains { $0.id == row.id || ($0.componentId == componentId && $0.title == title) }
            if duplicate { continue }
            file.scores.append(ScoreEntry(id: row.id, device: device, at: now, componentId: componentId, title: title, score: score, max: max))
            result.scoresAdded += 1
        }
    }
}
