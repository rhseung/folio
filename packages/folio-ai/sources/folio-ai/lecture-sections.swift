import FolioDomain
import Foundation

/// Claude's reading of a lecture's pages. Only a proposal: the add sheet shows it, and nothing is written until
/// the user approves (#321).
public struct LectureSectionDrafts: StructuredResult, Equatable {
    public struct Draft: Codable, Sendable, Equatable {
        public var title: String
        public var firstPage: Int
        /// A unit of the course, by its exact title; nil for a section that is a unit of its own.
        public var unit: String?

        public init(title: String, firstPage: Int, unit: String? = nil) {
            self.title = title
            self.firstPage = firstPage
            self.unit = unit
        }
    }

    public var sections: [Draft]

    public static let schema = Schema.object(["sections": Schema.array(Schema.object([
        "title": Schema.string,
        "firstPage": Schema.integer,
        "unit": Schema.nullable(Schema.string),
    ]))])
}

/// One page as Claude reads it to split a lecture (#450): its title, the start of the rest of its text, and a small
/// picture when the page has almost no text (a figure, a formula, a scanned slide) so it isn't read as blank.
public struct LecturePage: Sendable, Equatable {
    public var title: String?
    public var body: String
    /// JPEG.
    public var image: Data?

    public init(title: String?, body: String = "", image: Data? = nil) {
        self.title = title
        self.body = body
        self.image = image
    }

    /// Characters of body per page when the deck is short. A slide's first few lines say what it is about; the rest
    /// is detail that costs tokens without moving a boundary.
    public static let excerpt = 280
    /// Body across the whole deck: a long deck gets less per page rather than a bigger question.
    public static let budget = 36_000
    /// Under this, a page's own words don't say what it shows.
    public static let fewWords = 12
    /// Pictures per question, at about 250 tokens each at `thumbnail`.
    public static let maxImages = 24
    /// The long side of a page's picture, in pixels: enough to read a slide's heading and see what its figure is.
    public static let thumbnail: CGFloat = 512

    /// How much of each page's body a deck of `pages` gets.
    public static func excerptLength(pages: Int) -> Int {
        guard pages > 0 else { return excerpt }
        return max(min(excerpt, budget / pages), 60)
    }

    /// The start of a page's text with its title taken out and its whitespace run together, cut at a word.
    public static func excerpt(_ text: String, title: String?, limit: Int) -> String {
        var rest = text
        if let title, let range = rest.range(of: title) { rest.removeSubrange(range) }
        let words = rest.split(whereSeparator: \.isWhitespace)
        var out = ""
        for word in words {
            if out.count + word.count + 1 > limit {
                if out.isEmpty { out = String(word.prefix(limit)) }
                return out + "…"
            }
            out += out.isEmpty ? String(word) : " " + word
        }
        return out
    }

    /// Which pages (0-based) get a picture: those whose words are fewer than `fewWords`, spread evenly over the deck
    /// when there are more than `maxImages`, so a long run of figures at the end doesn't take them all.
    public static func pictured(words: [Int]) -> [Int] {
        let few = words.indices.filter { words[$0] < fewWords }
        guard few.count > maxImages else { return few }
        return (0..<maxImages).map { few[$0 * few.count / maxImages] }
    }
}

extension ClaudeClient {
    /// Claude reads each page's title, the start of its text and, for a page with little text, its picture, with the
    /// course's units, and says where each section starts and which unit it belongs to. The add sheet asks when the
    /// outline and slide titles say nothing, and both screens ask when the user presses "Claude로 나누기". Nil when the
    /// answer leaves nothing usable.
    public func lectureSections(file: String, pages: [LecturePage], units: [FolioDomain.Unit]) async throws -> LectureSplit? {
        let system: [ContentBlock] = [.text("""
        You split a university lecture's slides into the course's units. For each page you get its title (empty when \
        it has none) and the start of the rest of its text; a page with little text also comes as a small picture after \
        the text, labelled with its page number. You also get the course's unit outline. Read what the pages are about, \
        not just their titles: a section starts where the lecture moves on to another topic of the size of a unit or \
        a chapter's section, often at a divider or outline slide, not at every slide. A lecture usually has two to \
        eight. Give the sections in page order, each with the page it starts on and a short title in the slides' own \
        words. Set "unit" to the exact title of the course unit the section belongs to, or null when no unit fits. \
        Never invent a unit title.
        """)]
        let messages = [Message(role: .user, content: Self.lectureQuestion(file: file, pages: pages, units: units))]
        let drafts = try await run(.lectureSections, LectureSectionDrafts.self, system: system, messages: messages)
        return Self.split(drafts, pageCount: pages.count, units: units)
    }

    /// The text first and the pictures after it, each under its page number: one long text block keeps the pages in
    /// order to read, and a picture only has to say which page it is.
    static func lectureQuestion(file: String, pages: [LecturePage], units: [FolioDomain.Unit]) -> [ContentBlock] {
        let outline = UnitTree.outline(units).map { String(repeating: "  ", count: $0.depth) + "- " + $0.unit.title }
        let limit = LecturePage.excerptLength(pages: pages.count)
        let lines = pages.enumerated().map { i, page in
            let body = LecturePage.excerpt(page.body, title: page.title, limit: limit)
            let picture = page.image == nil ? "" : " [picture below]"
            return "## \(i + 1): \(page.title ?? "")\(picture)" + (body.isEmpty ? "" : "\n" + body)
        }
        var blocks: [ContentBlock] = [.text("""
        <file>\(file)</file>
        <units>
        \(outline.isEmpty ? "(none)" : outline.joined(separator: "\n"))
        </units>
        <pages count="\(pages.count)">
        \(lines.joined(separator: "\n"))
        </pages>
        """)]
        for (i, page) in pages.enumerated() {
            guard let image = page.image else { continue }
            blocks.append(.text("Page \(i + 1):"))
            blocks.append(.image(image, mediaType: "image/jpeg"))
        }
        return blocks
    }

    /// Drafts as a split: a unit Claude named is taken only when it is one of the course's (by exact title), and every
    /// other section becomes a new unit of its title.
    static func split(_ drafts: LectureSectionDrafts, pageCount: Int, units: [FolioDomain.Unit]) -> LectureSplit? {
        let found = drafts.sections.map { (section: LectureSplit.Section(title: LectureReading.clean($0.title), firstPage: $0.firstPage, lastPage: $0.firstPage), unit: $0.unit) }
        guard var split = LectureSplit(found.map(\.section), pageCount: pageCount) else { return nil }
        // By id: tidying moves first pages and drops sections past the file.
        let named = Dictionary(keepingFirst: found.map { ($0.section.id, $0.unit) })
        for (i, section) in split.sections.enumerated() {
            if let title = named[section.id] ?? nil, let unit = units.first(where: { $0.title == title }) {
                split.setUnit(unit.id, of: i, match: .claude)
            } else {
                split.makeNew(i)
            }
        }
        return split
    }
}
