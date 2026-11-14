import Foundation

public struct TranscriptionHints: Sendable, Equatable {
    public var title: String
    // 프롬프트가 끝에서부터 잘리므로 중요한 용어가 앞에 온다.
    public var terms: [String]

    public init(title: String, terms: [String]) {
        self.title = title
        self.terms = terms
    }

    // Whisper는 프롬프트를 바로 앞에 말한 글로 읽는다. 영어 강의에서는 한국어 틀 낱말을 언어를 바꾸라는 신호로 읽으므로
    // 한국어 틀 낱말을 넣지 않는다.
    public func prompt(terms count: Int? = nil) -> String {
        let shown = terms.prefix(count ?? terms.count)
        return shown.isEmpty ? "\(title)." : "\(title). \(shown.joined(separator: ", "))."
    }
}

public struct LecturePages: Codable, Sendable, Equatable {
    public var path: String
    public var first: Int?
    public var last: Int?
    public var materialId: UUID?

    public init(path: String, first: Int? = nil, last: Int? = nil, materialId: UUID? = nil) {
        self.path = path
        self.first = first
        self.last = last
        self.materialId = materialId
    }
}

public struct TranscriptionContext: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case recording
        case session
        case tagged
        case week
    }

    public var source: Source?
    public var slides: [LecturePages]
    public var topics: [String]
    public var terms: [String]

    public init(source: Source?, slides: [LecturePages], topics: [String], terms: [String] = []) {
        self.source = source
        self.slides = slides
        self.topics = topics
        self.terms = terms
    }

    // 새 판이 더한 출처는 받아쓰기 전체를 실패시키지 않고 알 수 없는 값으로 읽는다.
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

    public func hints(course title: String) -> TranscriptionHints {
        var seen = Set<String>()
        return TranscriptionHints(title: title, terms: (topics + terms).filter { seen.insert($0.lowercased()).inserted })
    }

    public func differs(from current: TranscriptionContext) -> Bool {
        func key(_ s: LecturePages) -> String { "\(s.materialId?.uuidString ?? s.path) \(s.first ?? 0) \(s.last ?? 0)" }
        return source != current.source || slides.map(key) != current.slides.map(key) || topics != current.topics
    }
}

extension CourseFile {
    public func transcriptionContext(for session: Session, recording: Recording? = nil) -> TranscriptionContext {
        let slides = lectureSlides(for: session, recording: recording)
        return TranscriptionContext(source: slides.source, slides: slides.pages, topics: transcriptionTopics(for: session))
    }

    func transcriptionTopics(for session: Session) -> [String] {
        unitsCovering(session: session.id).compactMap { id in units.first { $0.id == id }?.title }
    }

    public func lectureSlides(for session: Session, recording: Recording? = nil) -> (
        source: TranscriptionContext.Source?, pages: [LecturePages]
    ) {
        func pages(_ link: SessionMaterial) -> LecturePages? {
            materials.first { $0.id == link.materialId && $0.isPDF }.map {
                LecturePages(path: $0.path, first: link.firstPage, last: link.lastPage, materialId: $0.id)
            }
        }
        let viewed = (recording?.viewedPages() ?? []).compactMap(pages)
        if !viewed.isEmpty { return (.recording, viewed) }

        let linked = session.materials.compactMap(pages)
        let rest = materials(of: .session(session.id))
            .filter { item in item.material.isPDF && !linked.contains { $0.materialId == item.material.id } }
        let unitOnly = rest.filter { !$0.routes.contains(.direct) }
        let whole = rest.map(\.material).sorted { $0.path < $1.path }.map { LecturePages(path: $0.path, materialId: $0.id) }
        if !linked.isEmpty || !whole.isEmpty { return (unitOnly.isEmpty ? .session : .tagged, linked + whole) }

        let week =
            materials
            .filter {
                $0.isPDF && $0.path.hasPrefix(CourseFolder.lectures.rawValue + "/")
                    && StandardLayout.lectureWeek(($0.path as NSString).lastPathComponent) == session.week
            }
            .sorted { $0.path < $1.path }
            .map { LecturePages(path: $0.path, materialId: $0.id) }
        return (week.isEmpty ? nil : .week, week)
    }

    @discardableResult
    public mutating func linkViewedPages(of recording: Recording) -> Int {
        guard let session = recording.sessionId, let s = sessions.firstIndex(where: { $0.id == session }) else { return 0 }
        var linked = 0
        for range in recording.viewedPages() where !sessions[s].materials.contains(where: { $0.materialId == range.materialId }) {
            guard let material = materials.first(where: { $0.id == range.materialId }) else { continue }
            var pages = range.pageRange
            // 렉처의 한 쪽은 한 수업의 것이다(`Session.progressOverlap`). 다른 수업이 가진 쪽은 다시 훑어본 것이므로, 그 쪽만
            // 본 녹음은 아무것도 더하지 않는다.
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
            if i + 1 < words.count, isTerm(words[i + 1].text), words[i + 1].text.lowercased() != word.text.lowercased(),
                text[word.range.upperBound..<words[i + 1].range.lowerBound] == " "
            {
                add("\(word.text) \(words[i + 1].text)", at: i)
            }
        }

        let kept = counts.filter { key, entry in
            key.contains(" ") ? entry.count >= 2 : true
        }
        // Whisper의 프롬프트는 끝에서부터 용어를 버리므로, 동점의 순서를 사전 순서에 맡기면 같은 슬라이드가 실행마다 다른
        // 프롬프트를 만든다. 그래서 순서를 완전히 정한다. 두 낱말 용어는 그 첫 낱말보다 앞에 둔다.
        return
            kept
            .sorted { a, b in
                (a.value.count, -a.value.first, a.key.count, b.key) > (b.value.count, -b.value.first, b.key.count, a.key)
            }
            .prefix(limit)
            .map(\.value)
            .map { entry in
                entry.forms.max { a, b in a.value < b.value || (a.value == b.value && a.key > b.key) }!.key
            }
    }

    static func isTerm(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard !stopwords.contains(lower) else { return false }
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
