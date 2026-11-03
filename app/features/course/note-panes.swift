import Foundation

/// What the note panel shows. A narrow panel can't fit two columns, so there `split` shows the source alone.
struct NotePanes: Equatable {
    enum Mode: Hashable { case read, split, write }

    private(set) var mode = Mode.split
    /// The way back from reading, so ⌘E and a narrow panel's 편집 return to the column(s) last written in.
    private(set) var editing = Mode.split

    func shown(wide: Bool) -> Mode { mode == .split && !wide ? .write : mode }

    mutating func choose(_ mode: Mode) {
        self.mode = mode
        if mode != .read { editing = mode }
    }

    /// A narrow panel offers only reading and writing; writing there brings back the split too, should the panel widen.
    mutating func chooseNarrow(_ mode: Mode) { choose(mode == .read ? .read : editing) }

    mutating func toggle() { choose(mode == .read ? editing : .read) }
}
