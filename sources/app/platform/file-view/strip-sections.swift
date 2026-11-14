import FolioDomain
import SwiftUI

struct StripSection: Identifiable, Equatable {
    enum Kind: Equatable {
        case held
        case new
        case none

        var tinted: Bool { self != .none }
    }

    let id: UUID
    let pages: ClosedRange<Int>
    let title: String
    var kind: Kind = .held

    var label: String { Session.pagesLabel(pages) }
}

// 머리는 따로 된 항목이 아니라 첫 쪽 항목의 일부이다. 그래야 스크롤했을 때 둘이 함께 보인다. 형제 항목으로 두면 머리가 쪽의 id를 가져가서, 이동하면 머리와 그 아래 쪽이 보였다.
struct StripItem: Identifiable, Equatable {
    enum Lead: Equatable {
        case header(StripSection, open: Bool)
        case edit(StripSection)
        case draft(ClosedRange<Int>)
    }

    enum ID: Hashable { case page(Int), folded(UUID) }

    enum Mark: Equatable {
        case plain
        case tinted(last: Bool)
        case picked
    }

    let lead: Lead?
    let page: Int?
    let mark: Mark
    var trail: Lead? = nil

    var id: ID {
        if let page { return .page(page) }
        if case .header(let s, _)? = lead { return .folded(s.id) }
        return .folded(UUID())
    }

    static func column(
        pageCount: Int, sections: [StripSection], editing: UUID?, draft: ClosedRange<Int>?, draftBelow: Bool = false,
        isOpen: (StripSection) -> Bool
    ) -> [StripItem] {
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
                    items += draft.map {
                        StripItem(lead: nil, page: $0, mark: .picked, trail: $0 == draft.upperBound ? .draft(draft) : nil)
                    }
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
