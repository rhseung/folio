import Foundation

public enum SearchKind: String, CaseIterable, Sendable {
    case note, material, assignment, session, unit, quiz
}

/// One searchable thing in a course. `id` is the entity to open.
public struct SearchItem: Sendable, Hashable {
    public var kind: SearchKind
    public var courseId: UUID
    public var id: UUID
    public var title: String
    public var body: String

    public init(kind: SearchKind, courseId: UUID, id: UUID, title: String, body: String = "") {
        self.kind = kind
        self.courseId = courseId
        self.id = id
        // File names on Apple file systems often come back decomposed (NFD) while typed Hangul is composed (NFC);
        // without this, `강의` typed never matches a file named `강의`.
        self.title = title.precomposedStringWithCanonicalMapping
        self.body = body.precomposedStringWithCanonicalMapping
    }
}

public struct SearchHit: Sendable, Hashable {
    public var item: SearchItem
    /// Body text around the first match, when the title alone didn't match.
    public var snippet: String?
}

/// Ranking and snippets over the rows the SQLite index (FolioIndex `SearchStore`) found (docs/SPEC.md "검색").
public struct SearchIndex: Sendable {
    public var items: [SearchItem]

    public init(_ items: [SearchItem]) {
        self.items = items
    }

    /// Every word of the query must appear in the title or body. Title matches rank above body matches:
    /// exact title, then title prefix, then title contains, then body; shorter titles first within a rank.
    public func search(_ query: String, limit: Int = 60) -> [SearchHit] {
        let words = query.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        var ranked: [(rank: Int, hit: SearchHit)] = []
        for item in items {
            let inTitle = words.map { item.title.range(of: $0, options: options) != nil }
            guard zip(words, inTitle).allSatisfy({ $1 || item.body.range(of: $0, options: options) != nil }) else { continue }
            let rank: Int
            if !inTitle.allSatisfy({ $0 }) {
                rank = 3
            } else if item.title.compare(words.joined(separator: " "), options: options) == .orderedSame {
                rank = 0
            } else if item.title.range(of: words[0], options: options.union(.anchored)) != nil {
                rank = 1
            } else {
                rank = 2
            }
            let bodyWord = zip(words, inTitle).first { !$1 }?.0
            ranked.append((rank, SearchHit(item: item, snippet: bodyWord.flatMap { Self.snippet(of: $0, in: item.body, options: options) })))
        }
        return ranked
            .sorted { ($0.rank, $0.hit.item.title.count, $0.hit.item.title) < ($1.rank, $1.hit.item.title.count, $1.hit.item.title) }
            .prefix(limit)
            .map(\.hit)
    }

    static func snippet(of word: String, in body: String, options: String.CompareOptions) -> String? {
        guard let range = body.range(of: word, options: options) else { return nil }
        let start = body.index(range.lowerBound, offsetBy: -30, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: 60, limitedBy: body.endIndex) ?? body.endIndex
        let text = body[start..<end].split(whereSeparator: \.isNewline).joined(separator: " ")
        return (start > body.startIndex ? "…" : "") + text + (end < body.endIndex ? "…" : "")
    }

    /// A course's searchable items. `notes` carry their body without frontmatter; notes without an ID can't be opened and are left out.
    /// `cards` come from the course's quiz files, which live apart from course.json.
    public static func items(for file: CourseFile, notes: [(id: UUID, title: String, body: String)], cards: [QuizCard] = []) -> [SearchItem] {
        let course = file.course.id
        return notes.map { SearchItem(kind: .note, courseId: course, id: $0.id, title: $0.title, body: $0.body) }
            + file.materials.filter { $0.status != .ignored }.map {
                SearchItem(kind: .material, courseId: course, id: $0.id, title: ($0.path as NSString).lastPathComponent, body: $0.path)
            }
            + file.assignments.map { SearchItem(kind: .assignment, courseId: course, id: $0.id, title: $0.title, body: $0.memo) }
            + file.sessions.map { SearchItem(kind: .session, courseId: course, id: $0.id, title: $0.topic.isEmpty ? $0.name(among: file.sessions) : "\($0.name(among: file.sessions)) · \($0.topic)") }
            + file.units.map { SearchItem(kind: .unit, courseId: course, id: $0.id, title: $0.title) }
            + cards.map { SearchItem(kind: .quiz, courseId: course, id: $0.id, title: $0.prompt, body: $0.answer) }
    }
}
