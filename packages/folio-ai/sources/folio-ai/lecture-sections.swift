import FolioDomain
import Foundation

/// Claude's reading of a lecture's page titles. Only a proposal: the add sheet shows it, and nothing is written until
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

extension ClaudeClient {
    /// When the outline and slide titles don't say where a lecture's units begin: Claude reads each page's title and
    /// the course's units, and says where each section starts and which unit it belongs to. Nil when the answer
    /// leaves nothing usable.
    public func lectureSections(file: String, pageTitles: [String?], units: [FolioDomain.Unit]) async throws -> LectureSplit? {
        let outline = UnitTree.outline(units).map { String(repeating: "  ", count: $0.depth) + "- " + $0.unit.title }
        let pages = pageTitles.enumerated().map { i, t in "\(i + 1): \(t ?? "")" }
        let system: [ContentBlock] = [.text("""
        You split a university lecture's slides into the course's units. You get each page's title (empty when the page \
        has none) and the course's unit outline. Give the sections in page order, each with the page it starts on and \
        a short title taken from the slides. Start a section only where the topic changes to another unit or chapter, \
        not at every slide: a lecture usually has two to eight. Set "unit" to the exact title of the course unit the \
        section belongs to, or null when no unit fits. Never invent a unit title.
        """)]
        let ask = ContentBlock.text("""
        <file>\(file)</file>
        <units>
        \(outline.isEmpty ? "(none)" : outline.joined(separator: "\n"))
        </units>
        <pages>
        \(pages.joined(separator: "\n"))
        </pages>
        """)
        let drafts = try await run(.lectureSections, LectureSectionDrafts.self, system: system, messages: [Message(role: .user, content: [ask])])
        return Self.split(drafts, pageCount: pageTitles.count, units: units)
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
