import FolioDomain
import Foundation

struct SplitStrip: Equatable {
    private(set) var editing: UUID?
    private(set) var before: LectureSplit?
    private(set) var anchor: Int?
    private(set) var folded: Set<UUID> = []

    static func sections(_ split: LectureSplit, name: (Int) -> String) -> [StripSection] {
        split.sections.enumerated().map { i, s in
            StripSection(id: s.id, pages: s.pages, title: name(i), kind: s.unit == nil ? .none : s.isNew ? .new : .held)
        }
    }

    func items(_ split: LectureSplit, name: (Int) -> String) -> [StripItem] {
        StripItem.column(pageCount: split.pageCount, sections: Self.sections(split, name: name), editing: editing, draft: nil) {
            !folded.contains($0.id)
        }
    }

    func itemID(showing page: Int, in split: LectureSplit) -> StripItem.ID {
        let s = split.sections[split.section(at: page)]
        return folded.contains(s.id) && s.id != editing ? .folded(s.id) : .page(page)
    }

    func index(in split: LectureSplit) -> Int? { editing.flatMap { id in split.sections.firstIndex { $0.id == id } } }

    func changed(_ split: LectureSplit) -> Bool { before.map { $0 != split } ?? false }

    mutating func toggle(_ section: UUID) {
        if folded.contains(section) { folded.remove(section) } else { folded.insert(section) }
    }

    mutating func edit(_ section: UUID, in split: LectureSplit) {
        guard editing != section else { return }
        guard let s = split.sections.first(where: { $0.id == section }) else { return }
        editing = section
        before = split
        anchor = s.firstPage
    }

    mutating func start(at page: Int, in split: LectureSplit) {
        edit(split.sections[split.section(at: page)].id, in: split)
    }

    mutating func press(_ page: Int) {
        done()
        anchor = page
    }

    mutating func extend(to page: Int, in split: inout LectureSplit) {
        if let i = index(in: split) {
            split.moveEdge(of: i, to: page)
            return
        }
        let from = anchor ?? page
        let was = split
        let i = split.carve(min(from, page)...max(from, page))
        editing = split.sections[i].id
        before = was
        anchor = from
        folded.remove(split.sections[i].id)
    }

    mutating func cancel(_ split: inout LectureSplit) {
        if let before { split = before }
        done()
    }

    mutating func done() {
        editing = nil
        before = nil
    }
}
