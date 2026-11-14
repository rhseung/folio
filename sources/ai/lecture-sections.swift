import FolioDomain
import Foundation

extension ClaudeClient {
    public func lectureSections(file: String, pages: [LecturePage], units: [FolioDomain.Unit]) async throws -> LectureSplit? {
        let system: [ContentBlock] = [
            .text(
                """
                You split a university lecture's slides into the course's units. For each page you get its title (empty when \
                it has none) and the start of the rest of its text. Some pages also come as a small picture after the text, \
                labelled with its page number: pages with little text, pages that are mostly figures, and pages whose text \
                repeats an earlier page's. You also get the course's unit outline. Read what the pages are about, not just \
                their titles: a section starts where the lecture moves on to another topic of the size of a unit or a \
                chapter's section, often at a divider or outline slide, not at every slide. A lecture usually has two to \
                eight. A deck often shows its roadmap again before each part with that part highlighted; look at the picture \
                to see which item is highlighted, and start a section there only when the highlight moves to another \
                top-level item, not to a sub-item of the part already under way. When the course has units, split at the \
                level of its most specific units. Give the sections in page order, each with the page it starts on and a \
                short title in the slides' own words. Set "unit" to the exact title of the most specific course unit the \
                section belongs to, or null when no unit fits. Never invent a unit title. Set "skip" to true for pages that \
                belong to no unit, such as a title page, an appendix or extra slides at the end, and false otherwise.
                """)
        ]
        let messages = [Message(role: .user, content: Self.lectureQuestion(file: file, pages: pages, units: units))]
        let drafts = try await run(.lectureSections, LectureSectionDrafts.self, system: system, messages: messages)
        return Self.split(drafts, pageCount: pages.count, units: units)
    }

    static func lectureQuestion(file: String, pages: [LecturePage], units: [FolioDomain.Unit]) -> [ContentBlock] {
        let outline = UnitTree.outline(units).map { String(repeating: "  ", count: $0.depth) + "- " + $0.unit.title }
        let limit = LecturePage.excerptLength(pages: pages.count)
        let lines = pages.enumerated().map { i, page in
            let body = LecturePage.excerpt(page.body, title: page.title, limit: limit)
            let picture = page.image == nil ? "" : " [picture below]"
            return "## \(i + 1): \(page.title ?? "")\(picture)" + (body.isEmpty ? "" : "\n" + body)
        }
        var blocks: [ContentBlock] = [
            .text(
                """
                <file>\(file)</file>
                <units>
                \(outline.isEmpty ? "(none)" : outline.joined(separator: "\n"))
                </units>
                <pages count="\(pages.count)">
                \(lines.joined(separator: "\n"))
                </pages>
                """)
        ]

        for (i, page) in pages.enumerated() {
            guard let image = page.image else { continue }
            blocks.append(.text("Page \(i + 1):"))
            blocks.append(.image(image, mediaType: "image/jpeg"))
        }
        return blocks
    }

    static func split(_ drafts: LectureSectionDrafts, pageCount: Int, units: [FolioDomain.Unit]) -> LectureSplit? {
        let found = drafts.sections.map {
            (
                section: LectureSplit.Section(title: LectureReading.clean($0.title), firstPage: $0.firstPage, lastPage: $0.firstPage),
                draft: $0
            )
        }
        guard var split = LectureSplit(found.map(\.section), pageCount: pageCount) else { return nil }
        let drafted = Dictionary(keepingFirst: found.map { ($0.section.id, $0.draft) })
        for (i, section) in split.sections.enumerated() {
            let draft = drafted[section.id]
            if let title = draft?.unit, let unit = units.first(where: { $0.title == title }) {
                split.setUnit(unit.id, of: i, match: .claude)
            } else if draft?.skip == true {
                split.setUnit(nil, of: i)
            } else {
                split.makeNew(i)
            }
        }

        for i in split.sections.indices.dropFirst().reversed() {
            let (a, b) = (split.sections[i - 1], split.sections[i])
            if a.unit == b.unit, !a.isNew, !b.isNew { split.merge(after: i - 1) }
        }
        return split
    }
}
