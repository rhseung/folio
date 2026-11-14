import FolioMarkdown
import Foundation
import Observation

@MainActor @Observable
final class NoteOutlineModel {
    let views = NoteViews()
    private(set) var outline = NoteOutline(entries: [])
    private(set) var current: Int?
    // 제목 위에 글을 쓰면 인덱스가 바뀌므로 제목의 anchor로 기억한다.
    private var open: Set<String> = []
    @ObservationIgnored private var top = 1
    @ObservationIgnored private var text: String?
    // 끝 근처의 제목으로 뛰면 그 제목을 맨 위로 올릴 수 없고, 그때 생긴 스크롤이 위의 제목을 표시하게 된다. 그래서 이
    // 시각까지는 스크롤해도 표시를 옮기지 않는다.
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

struct NoteOutlineFit: Equatable {
    var besideSplit: Bool
    var besideOne: Bool

    init(width: CGFloat) {
        besideSplit = width >= NotePanes.sideBySide + Theme.Size.noteOutline
        besideOne = width >= NoteLook.measure + Theme.Size.noteOutline
    }

    func docks(_ shown: NotePanes.Mode) -> Bool { shown == .split ? besideSplit : besideOne }
}
