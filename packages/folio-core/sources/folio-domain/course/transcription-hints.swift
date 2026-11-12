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
public struct LecturePages: Codable, Sendable, Equatable {
    public var path: String
    public var first: Int?
    public var last: Int?
    /// The path is for showing; this says which file it was, renamed or not. Nil for a file no longer tracked.
    public var materialId: UUID?

    public init(path: String, first: Int? = nil, last: Int? = nil, materialId: UUID? = nil) {
        self.path = path
        self.first = first
        self.last = last
        self.materialId = materialId
    }
}

/// What a transcription was told about the class, kept in its transcript so the player can show it and notice when
/// the course's links have moved on since.
public struct TranscriptionContext: Codable, Sendable, Equatable {
    /// Why these slides: the first rule in `CourseFile.lectureSlides(for:recording:)` that found any.
    public enum Source: String, Codable, Sendable {
        /// Pages left on screen while recording.
        case recording
        /// Files linked to the session, with their page ranges.
        case session
        /// The session's files and its units' (parents included).
        case tagged
        /// `Lectures/` files named for the session's week.
        case week
    }

    /// Nil when no slides were found.
    public var source: Source?
    public var slides: [LecturePages]
    /// The session's units' titles, parents after.
    public var topics: [String]
    /// Read from the slides, most telling first.
    public var terms: [String]

    public init(source: Source?, slides: [LecturePages], topics: [String], terms: [String] = []) {
        self.source = source
        self.slides = slides
        self.topics = topics
        self.terms = terms
    }

    // A source a newer version adds reads as unknown rather than failing the whole transcript.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)).flatMap(Source.init(rawValue:))
        slides = try c.decodeIfPresent([LecturePages].self, forKey: .slides) ?? []
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        terms = try c.decodeIfPresent([String].self, forKey: .terms) ?? []
    }

    public func reading(_ slides: String) -> TranscriptionContext {
        var read = self
        read.terms = LectureTerms.terms(in: slides)
        return read
    }

    /// The topics before the slides' terms, each once.
    public func hints(course title: String) -> TranscriptionHints {
        var seen = Set<String>()
        return TranscriptionHints(title: title, terms: (topics + terms).filter { seen.insert($0.lowercased()).inserted })
    }

    /// Whether `current`, made from the course as it is now, would have told the recognizer something else. Terms
    /// are left out: knowing them means reading the PDFs again, and they follow from the slides anyway.
    public func differs(from current: TranscriptionContext) -> Bool {
        func key(_ s: LecturePages) -> String { "\(s.materialId?.uuidString ?? s.path) \(s.first ?? 0) \(s.last ?? 0)" }
        return source != current.source || slides.map(key) != current.slides.map(key) || topics != current.topics
    }
}

extension CourseFile {
    /// Everything but the terms, which need the slides read.
    public func transcriptionContext(for session: Session, recording: Recording? = nil) -> TranscriptionContext {
        let slides = lectureSlides(for: session, recording: recording)
        return TranscriptionContext(source: slides.source, slides: slides.pages, topics: transcriptionTopics(for: session))
    }

    /// Unit titles name what the class is about in the lecturer's own words ("NFA to DFA: The Subset Construction"),
    /// and most classes have units where few have slides linked. Parents follow their children: they are broader.
    func transcriptionTopics(for session: Session) -> [String] {
        unitsCovering(session: session.id).compactMap { id in units.first { $0.id == id }?.title }
    }

    /// The slides a class covered: the pages left on screen while `recording`, else the PDFs that belong with the
    /// session (`routes(of:to:)`), its own within their page ranges and then its units', else the week's files under
    /// `Lectures/` by their `05_` / `05-1_` prefix. What was on screen goes first because it is what the class did,
    /// where a link may be a whole file or a range set before the class. The session's and its units' files are
    /// merged rather than one shadowing the other: one handout linked to the class must not hide the chapter's slides.
    public func lectureSlides(for session: Session, recording: Recording? = nil) -> (source: TranscriptionContext.Source?, pages: [LecturePages]) {
        func pages(_ link: SessionMaterial) -> LecturePages? {
            materials.first { $0.id == link.materialId && $0.isPDF }.map { LecturePages(path: $0.path, first: link.firstPage, last: link.lastPage, materialId: $0.id) }
        }
        let viewed = (recording?.viewedPages() ?? []).compactMap(pages)
        if !viewed.isEmpty { return (.recording, viewed) }

        let linked = session.materials.compactMap(pages)
        let rest = materials(of: .session(session.id))
            .filter { item in item.material.isPDF && !linked.contains { $0.materialId == item.material.id } }
        let unitOnly = rest.filter { !$0.routes.contains(.direct) }
        let whole = rest.map(\.material).sorted { $0.path < $1.path }.map { LecturePages(path: $0.path, materialId: $0.id) }
        if !linked.isEmpty || !whole.isEmpty { return (unitOnly.isEmpty ? .session : .tagged, linked + whole) }

        let week = materials
            .filter { $0.isPDF && $0.path.hasPrefix(CourseFolder.lectures.rawValue + "/") && StandardLayout.lectureWeek(($0.path as NSString).lastPathComponent) == session.week }
            .sorted { $0.path < $1.path }
            .map { LecturePages(path: $0.path, materialId: $0.id) }
        return (week.isEmpty ? nil : .week, week)
    }

    /// Links the pages `recording` left on screen to its session, for files the session has no link to yet: a range
    /// the user set stays as it is. Returns how many files it linked.
    @discardableResult
    public mutating func linkViewedPages(of recording: Recording) -> Int {
        guard let session = recording.sessionId, let s = sessions.firstIndex(where: { $0.id == session }) else { return 0 }
        var linked = 0
        for range in recording.viewedPages() where !sessions[s].materials.contains(where: { $0.materialId == range.materialId }) {
            guard let material = materials.first(where: { $0.id == range.materialId }) else { continue }
            var pages = range.pageRange
            // A lecture page is one class's (`Session.progressOverlap`): pages another class took were gone back over,
            // and a recording that saw only those adds nothing.
            if material.role == .lecture {
                pages = pages.fitted(besides: pagesTaken(in: material.id, besides: session), pages: nil)
                guard pages.first != nil || pages.last != nil else { continue }
            }
            linkMaterial(range.materialId, session: session, firstPage: pages.first, lastPage: pages.last)
            linked += 1
        }
        return linked
    }
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
        // Fully ordered: Whisper's prompt drops terms from the end, so a tie left to the dictionary's order would
        // give the same slides a different prompt each run. A pair goes before the word it starts with.
        return kept
            .sorted { a, b in
                (a.value.count, -a.value.first, a.key.count, b.key) > (b.value.count, -b.value.first, b.key.count, a.key)
            }
            .prefix(limit)
            .map(\.value)
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
