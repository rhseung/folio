import FolioDomain
import Foundation

/// The split screen's thumbnail column (#321). `before` is the split as it was when a section was taken up, so 취소 can
/// put it back. The section being changed is also the one picked on the bar and in the rows, so picking it there shows
/// its pages here.
struct SplitStrip: Equatable {
    private(set) var editing: UUID?
    private(set) var before: LectureSplit?
    /// The page a range starts from: the last one pressed without ⇧.
    private(set) var anchor: Int?
    private(set) var folded: Set<UUID> = []

    /// Each section as the column heads it, named as the rows name it.
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

    /// Where the column scrolls for the PDF's page: the page, or the header of the folded section holding it.
    func itemID(showing page: Int, in split: LectureSplit) -> StripItem.ID {
        let s = split.sections[split.section(at: page)]
        return folded.contains(s.id) && s.id != editing ? .folded(s.id) : .page(page)
    }

    func index(in split: LectureSplit) -> Int? { editing.flatMap { id in split.sections.firstIndex { $0.id == id } } }

    /// What 적용 has to keep: nothing changed since the section was taken up.
    func changed(_ split: LectureSplit) -> Bool { before.map { $0 != split } ?? false }

    mutating func toggle(_ section: UUID) {
        if folded.contains(section) { folded.remove(section) } else { folded.insert(section) }
    }

    /// The header pressed, or the section picked on the bar or in its row. Taking up another section keeps what was
    /// changed on the one before, as the bar's edits are kept.
    mutating func edit(_ section: UUID, in split: LectureSplit) {
        guard editing != section else { return }
        guard let s = split.sections.first(where: { $0.id == section }) else { return }
        editing = section
        before = split
        anchor = s.firstPage
    }

    /// A long press, the touch screen's way in: the section holding the page.
    mutating func start(at page: Int, in split: LectureSplit) {
        edit(split.sections[split.section(at: page)].id, in: split)
    }

    /// A press without ⇧: goes to the page, and lets the section being changed go with its change kept.
    mutating func press(_ page: Int) {
        done()
        anchor = page
    }

    /// ⇧-press, or on a touch screen a tap while a section is being changed. On that section it moves the near edge
    /// to `page` (`LectureSplit.moveEdge`); with none, the pages from the last press to `page` become a section of
    /// their own (`carve`), which is then the one being changed, so 취소 takes the cut back too.
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

    /// 취소: the split as it was when the section was taken up.
    mutating func cancel(_ split: inout LectureSplit) {
        if let before { split = before }
        done()
    }

    /// 적용, or another press: the change stays in the split, which the screen's 저장 writes.
    mutating func done() {
        editing = nil
        before = nil
    }
}
