import Foundation

/// What a speech recognizer is told before it hears a class: the course and the terms on that class's slides. Told a
/// term, Whisper writes it in English letters ("left factoring"); untold, it spells the sound in Hangul ("레프트 팩터링")
/// or mishears it outright ("Shape Traders" for "shift-reduce").
public struct TranscriptionHints: Sendable, Equatable {
    public var title: String
    /// Most telling first.
    public var terms: [String]

    public init(title: String, terms: [String]) {
        self.title = title
        self.terms = terms
    }

    /// Whisper's prompt, read as text said just before. No Korean framing words: an English lecture would read them as
    /// a cue to switch language.
    public func prompt(terms count: Int? = nil) -> String {
        let shown = terms.prefix(count ?? terms.count)
        return shown.isEmpty ? "\(title)." : "\(title). \(shown.joined(separator: ", "))."
    }
}

/// Pages of a lecture file, 1-based; nil bounds are the file's ends.
public struct LecturePages: Sendable, Equatable {
    public var path: String
    public var first: Int?
    public var last: Int?

    public init(path: String, first: Int? = nil, last: Int? = nil) {
        self.path = path
        self.first = first
        self.last = last
    }
}

extension CourseFile {
    /// The course, the class's topic and units, then the terms on its slides.
    public func transcriptionHints(for session: Session, slides: String) -> TranscriptionHints {
        var seen = Set<String>()
        let terms = (transcriptionTopics(for: session) + LectureTerms.terms(in: slides)).filter { seen.insert($0.lowercased()).inserted }
        return TranscriptionHints(title: course.title, terms: terms)
    }

    /// Unit titles name what the class is about in the lecturer's own words ("NFA to DFA: The Subset Construction"),
    /// and most classes have units where few have slides linked. Parents follow their children: they are broader.
    func transcriptionTopics(for session: Session) -> [String] {
        let direct = units.filter { session.unitIds.contains($0.id) || $0.sessionIds.contains(session.id) }.sorted { $0.order < $1.order }
        var ids = Set(direct.map(\.id)), chain = direct
        var next = direct.compactMap(\.parentId)
        while let id = next.popLast() {
            guard ids.insert(id).inserted, let unit = units.first(where: { $0.id == id }) else { continue }
            chain.append(unit)
            if let parent = unit.parentId { next.append(parent) }
        }
        let topic = session.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return (topic.isEmpty ? [] : [topic]) + chain.map(\.title)
    }

    /// The slides a class covered: the PDFs linked to it within their page ranges, else the files linked to it or its
    /// units, else the week's files under `Lectures/` by their `05_` / `05-1_` prefix.
    public func lecturePages(for session: Session) -> [LecturePages] {
        let linked = session.materials.compactMap { link in
            materials.first { $0.id == link.materialId && $0.isPDF }.map { LecturePages(path: $0.path, first: link.firstPage, last: link.lastPage) }
        }
        if !linked.isEmpty { return linked }
        let unitIds = Set(session.unitIds + units.filter { $0.sessionIds.contains(session.id) }.map(\.id))
        let tagged = materials.filter { $0.isPDF && ($0.sessionIds.contains(session.id) || !unitIds.isDisjoint(with: $0.unitIds)) }
        if !tagged.isEmpty { return tagged.sorted { $0.path < $1.path }.map { LecturePages(path: $0.path) } }
        return materials
            .filter { $0.isPDF && $0.path.hasPrefix(CourseFolder.lectures.rawValue + "/") && Self.lectureWeek($0.path) == session.week }
            .sorted { $0.path < $1.path }
            .map { LecturePages(path: $0.path) }
    }

    static func lectureWeek(_ path: String) -> Int? {
        let name = (path as NSString).lastPathComponent
        guard let match = name.prefixMatch(of: /(\d{2})(-\d+)?_/) else { return nil }
        return Int(match.1)
    }
}

private extension Material {
    var isPDF: Bool { !isFolder && path.lowercased().hasSuffix(".pdf") }
}

/// The words on a slide worth telling a recognizer about. Korean it already hears well; what it gets wrong is the
/// English in between, so only Latin-script words count: names, acronyms, and two-word terms that recur.
public enum LectureTerms {
    public static func terms(in text: String, limit: Int = 40) -> [String] {
        let words = text.matches(of: /[A-Za-z][A-Za-z0-9]*(?:[-'][A-Za-z0-9]+)*/).map { (text: String($0.output), range: $0.range) }
        var counts: [String: (count: Int, first: Int, forms: [String: Int])] = [:]
        func add(_ term: String, at position: Int) {
            let key = term.lowercased()
            var entry = counts[key] ?? (0, position, [:])
            entry.count += 1
            entry.forms[term, default: 0] += 1
            counts[key] = entry
        }
        for (i, word) in words.enumerated() where isTerm(word.text) {
            add(word.text, at: i)
            // Two words in a row, with only a space between them on the slide.
            if i + 1 < words.count, isTerm(words[i + 1].text), words[i + 1].text.lowercased() != word.text.lowercased(),
               text[word.range.upperBound..<words[i + 1].range.lowerBound] == " " {
                add("\(word.text) \(words[i + 1].text)", at: i)
            }
        }
        let kept = counts.filter { key, entry in
            // A pair once is just two words that met; a pair is a term when it comes back.
            key.contains(" ") ? entry.count >= 2 : true
        }
        return kept.values
            .sorted { ($0.count, -$0.first) > ($1.count, -$1.first) }
            .prefix(limit)
            .map { entry in
                // The spelling the slides use most, the first one on a tie.
                entry.forms.max { a, b in a.value < b.value || (a.value == b.value && a.key > b.key) }!.key
            }
    }

    static func isTerm(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard !stopwords.contains(lower) else { return false }
        // `TCP`, `LL`: an acronym may be two letters; any other word needs three.
        return word.count >= 3 || (word.count == 2 && word == word.uppercased())
    }

    static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one", "our", "out", "has",
        "have", "him", "his", "how", "its", "may", "new", "now", "old", "see", "two", "way", "who", "did", "get", "let", "say",
        "she", "too", "use", "used", "using", "with", "this", "that", "from", "they", "will", "would", "there", "their", "what",
        "when", "which", "where", "while", "then", "than", "them", "these", "those", "into", "onto", "also", "each", "only",
        "some", "such", "more", "most", "other", "over", "same", "very", "just", "about", "after", "before", "between", "both",
        "does", "done", "here", "must", "should", "could", "been", "being", "were", "your", "yours", "ours", "via", "per",
        "is", "of", "to", "in", "on", "at", "by", "or", "an", "as", "be", "if", "it", "we", "so", "no", "do", "up",
        "page", "slide", "slides", "lecture", "chapter", "section", "figure", "fig", "example", "exercise", "note", "notes",
        "http", "https", "www", "com", "org", "edu", "pdf", "etc",
    ]
}
