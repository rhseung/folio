import FolioDomain
import SwiftUI

/// A run of a PDF's pages under one header in a thumbnail column: a class's progress in the page strip (#147), or a
/// unit's zone on the split screen (#321). Both columns lay it out with `StripItem.column` and draw it with the views
/// below, so a section reads the same in either place.
struct StripSection: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A class's pages, or a unit's: on the course's tint, under a course-colour chevron.
        case held
        /// A unit made when the split is saved: on the tint too, its name in the course's ink as a range not saved yet
        /// names itself.
        case new
        /// Pages that go to no unit: no tint and a grey chevron, as pages with no progress have neither.
        case none

        var tinted: Bool { self != .none }
    }

    /// The class's or the split section's id.
    let id: UUID
    let pages: ClosedRange<Int>
    /// `10/28(수)`, or the unit's title.
    let title: String
    var kind: Kind = .held

    var label: String { Session.pagesLabel(pages) }
}

/// One page with what heads it, or a folded section's header alone. A header is part of its first page's item rather
/// than an item of its own: scrolled to, the two come into view together. As siblings the header took the page's id,
/// and a jump showed it with the page below.
struct StripItem: Identifiable, Equatable {
    enum Lead: Equatable {
        case header(StripSection, open: Bool)
        /// The section being changed: its header turned into the row its range is changed from.
        case edit(StripSection)
        /// The row a new range is saved from, above its pages.
        case draft(ClosedRange<Int>)
    }

    enum ID: Hashable { case page(Int), folded(UUID) }

    enum Mark: Equatable {
        case plain
        /// On its section's tint, which ends under the section's last page, or under a folded section's header.
        case tinted(last: Bool)
        /// In the range being picked or changed.
        case picked
    }

    let lead: Lead?
    let page: Int?
    let mark: Mark
    /// Under the page: a new range's row when it was picked downward, at the end ⇧ set.
    var trail: Lead? = nil

    var id: ID {
        if let page { return .page(page) }
        if case .header(let s, _)? = lead { return .folded(s.id) }
        return .folded(UUID())
    }

    /// The column top to bottom: pages no section holds, each section's header with its pages when unfolded, the
    /// section being changed under its edit row, and a new range with its draft row over it, or under it when
    /// `draftBelow`.
    static func column(pageCount: Int, sections: [StripSection], editing: UUID?, draft: ClosedRange<Int>?, draftBelow: Bool = false,
                       isOpen: (StripSection) -> Bool) -> [StripItem] {
        func run(_ pages: ClosedRange<Int>, lead: Lead, mark: (Int) -> Mark) -> [StripItem] {
            pages.map { StripItem(lead: $0 == pages.lowerBound ? lead : nil, page: $0, mark: mark($0)) }
        }
        var items: [StripItem] = []
        var page = 1
        while page <= pageCount {
            if let s = sections.first(where: { $0.pages.lowerBound == page }) {
                if s.id == editing {
                    items += run(s.pages, lead: .edit(s)) { _ in .picked }
                } else if isOpen(s) {
                    items += run(s.pages, lead: .header(s, open: true)) { s.kind.tinted ? .tinted(last: $0 == s.pages.upperBound) : .plain }
                } else {
                    items.append(StripItem(lead: .header(s, open: false), page: nil, mark: s.kind.tinted ? .tinted(last: true) : .plain))
                }
                page = s.pages.upperBound + 1
            } else if let draft, draft.lowerBound == page {
                if draftBelow {
                    items += draft.map { StripItem(lead: nil, page: $0, mark: .picked, trail: $0 == draft.upperBound ? .draft(draft) : nil) }
                } else {
                    items += run(draft, lead: .draft(draft)) { _ in .picked }
                }
                page = draft.upperBound + 1
            } else {
                items.append(StripItem(lead: nil, page: page, mark: .plain))
                page += 1
            }
        }
        return items
    }
}
