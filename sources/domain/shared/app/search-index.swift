import Foundation

public struct SearchIndex: Sendable {
    public var items: [SearchItem]

    public init(_ items: [SearchItem]) {
        self.items = items
    }

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
            ranked.append(
                (rank, SearchHit(item: item, snippet: bodyWord.flatMap { Self.snippet(of: $0, in: item.body, options: options) })))
        }

        return
            ranked
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

    public static func items(
        for file: CourseFile, notes: [(id: UUID, title: String, body: String)], cards: [QuizCard] = [],
        calendar: Calendar = .current
    ) -> [SearchItem] {
        let course = file.course.id
        return notes.map { SearchItem(kind: .note, courseId: course, id: $0.id, title: $0.title, body: $0.body) }
            + file.materials.filter { $0.status != .ignored }.map {
                SearchItem(kind: .material, courseId: course, id: $0.id, title: ($0.path as NSString).lastPathComponent, body: $0.path)
            }
            + file.assignments.map { SearchItem(kind: .assignment, courseId: course, id: $0.id, title: $0.title, body: $0.memo) }
            + file.exams.map { SearchItem(kind: .exam, courseId: course, id: $0.id, title: $0.title, body: $0.scopeText) }
            + file.sessions.map {
                SearchItem(
                    kind: .session, courseId: course, id: $0.id, title: file.title(of: $0, calendar: calendar),
                    body: file.reference(of: $0, calendar: calendar))
            }
            + file.units.map { SearchItem(kind: .unit, courseId: course, id: $0.id, title: $0.title) }
            + cards.map { SearchItem(kind: .quiz, courseId: course, id: $0.id, title: $0.prompt, body: $0.answer) }
    }
}
