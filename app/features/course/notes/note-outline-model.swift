import FolioMarkdown
import Foundation
import Observation

/// The outline beside a note (#387): its headings, the one being read, and the deep ones opened. Which lines are
/// headings and how they fold is `NoteOutline`'s; this keeps what the screen does with it.
@MainActor @Observable
final class NoteOutlineModel {
    let views = NoteViews()
    private(set) var outline = NoteOutline(entries: [])
    /// The heading the reader is in.
    private(set) var current: Int?
    /// Deep headings opened under these, by the heading's anchor: indices move as headings are written above.
    private var open: Set<String> = []
    @ObservationIgnored private var top = 1
    @ObservationIgnored private var text: String?
    /// Until then a scroll doesn't move the mark: a jump to a heading near the end can't bring it to the top, and the
    /// scroll it makes would mark the heading above.
    @ObservationIgnored private var held: Date?
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
        views.scrolled = { [weak self] line in self?.scrolled(line) }
    }

    struct Row: Identifiable, Equatable {
        let index: Int
        let title: String
        let indent: Int
        /// Deep headings fold under it, and whether they are open.
        let folds: Bool
        let open: Bool
        let marked: Bool
        var id: Int { index }
    }

    var isEmpty: Bool { outline.entries.isEmpty }

    var rows: [Row] {
        let opened = openIndices
        let marked = outline.marked(current, open: opened)
        return outline.shown(open: opened).map { i in
            Row(
                index: i, title: outline.entries[i].title, indent: outline.indent(i), folds: outline.folds(i), open: opened.contains(i),
                marked: i == marked)
        }
    }

    private var openIndices: Set<Int> {
        Set(outline.entries.indices.filter { open.contains(outline.entries[$0].anchor) })
    }

    func read(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        let next = NoteOutline(text)
        if next != outline { outline = next }
        mark(outline.current(at: top))
    }

    func scrolled(_ line: Int) {
        top = line
        if let held, now() < held { return }
        held = nil
        mark(outline.current(at: line))
    }

    func jump(_ index: Int) {
        guard outline.entries.indices.contains(index) else { return }
        let entry = outline.entries[index]
        top = entry.line
        held = now().addingTimeInterval(0.6)
        mark(index)
        views.show(line: entry.line, location: entry.location)
    }

    func toggle(_ index: Int) {
        guard outline.entries.indices.contains(index) else { return }
        let anchor = outline.entries[index].anchor
        if open.contains(anchor) { open.remove(anchor) } else { open.insert(anchor) }
    }

    private func mark(_ index: Int?) {
        if index != current { current = index }
    }
}

/// Where the outline goes: beside the note when the panel has room for it and what it shows, else in the bar
/// button's popover.
struct NoteOutlineFit: Equatable {
    /// Room beside the source and the preview side by side, and beside one of them.
    var besideSplit: Bool
    var besideOne: Bool

    init(width: CGFloat) {
        besideSplit = width >= NotePanes.sideBySide + Theme.Size.noteOutline
        besideOne = width >= NoteLook.measure + Theme.Size.noteOutline
    }

    func docks(_ shown: NotePanes.Mode) -> Bool { shown == .split ? besideSplit : besideOne }
}
