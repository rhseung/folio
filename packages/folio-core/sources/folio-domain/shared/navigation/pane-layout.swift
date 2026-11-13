import Foundation

/// How a note pane shows its note: the preview, the source beside the preview, or the source.
public enum NoteViewMode: String, Codable, Sendable, CaseIterable {
    case read, split, write
}

/// The panes of one tab, left to right (#62). Each pane draws one address (#43) and takes its share of the width.
/// There is no cap on how many (2026-11-12 사용자): a pane never leaves the layout, or goes to a tab of its own,
/// because the window is narrow; `fold` puts it in a bundle at the row's end instead. A tab split by the width would
/// not join again when the width came back, so resizing a window or turning an iPad would change the layout.
public struct PaneLayout: Hashable, Sendable {
    public struct Pane: Hashable, Sendable {
        public var link: AppLink
        public fileprivate(set) var share: Double
        /// How a note shown here is shown. It travels with the layout, so a session's layout brings its note back the
        /// way it was left.
        public var noteMode: NoteViewMode?
        /// Folded by hand ("칸 접기"): a strip at any width until it is pressed.
        public fileprivate(set) var collapsed = false
        // The layout's clock when this pane was last pressed. A tick, not a date: two presses in the same instant
        // must still order, and a restored layout must not fold by when the device was last used.
        fileprivate var pressed: Int

        fileprivate init(link: AppLink, share: Double, noteMode: NoteViewMode? = nil, collapsed: Bool = false, pressed: Int) {
            self.link = link
            self.share = share
            self.noteMode = noteMode
            self.collapsed = collapsed
            self.pressed = pressed
        }
    }

    /// The smallest share a drag leaves a pane, so a divider can't swallow a pane whole; folding is `fold`'s job.
    public static let minShare = 0.1

    public private(set) var panes: [Pane]
    /// The pane last pressed. The tab's place, history and back and forward follow it.
    public private(set) var focus: Int
    private var clock: Int

    public init(_ link: AppLink) {
        panes = [Pane(link: link, share: 1, pressed: 0)]
        focus = 0
        clock = 0
    }

    /// The links, focused on the first. Shares that don't fit the links (missing, or not all positive) fall back to
    /// even ones. Nil without a link.
    public init?(links: [AppLink], shares: [Double]? = nil) {
        guard !links.isEmpty else { return nil }
        var shares = shares.map { Array($0.prefix(links.count)) } ?? []
        if shares.count != links.count || shares.contains(where: { !($0 > 0) || !$0.isFinite }) {
            shares = Array(repeating: 1, count: links.count)
        }
        let total = shares.reduce(0, +)
        // The first pane is the newest press, so the last ones fold first.
        panes = zip(links, shares).enumerated().map { i, pair in
            Pane(link: pair.0, share: pair.1 / total, pressed: links.count - 1 - i)
        }
        focus = 0
        clock = links.count - 1
    }

    public var links: [AppLink] { panes.map(\.link) }
    public var shares: [Double] { panes.map(\.share) }
    public var focused: Pane { panes[focus] }
    public var collapsed: Set<Int> { Set(panes.indices.filter { panes[$0].collapsed }) }

    /// Pressing a pane folded by hand opens it again: its strip is the only place left to press.
    public mutating func press(_ i: Int) {
        guard panes.indices.contains(i) else { return }
        clock += 1
        panes[i].pressed = clock
        panes[i].collapsed = false
        focus = i
    }

    /// Whether "칸 접기" can fold pane `i`: not while it is the last pane open.
    public func canCollapse(_ i: Int) -> Bool {
        panes.indices.contains(i) && !panes[i].collapsed && panes.indices.contains { $0 != i && !panes[$0].collapsed }
    }

    /// "칸 접기": pane `i` folds to its strip and stays folded however wide the window grows, until it is pressed
    /// (2026-11-08 사용자). The focus, which never folds, moves to the open pane pressed most recently.
    public mutating func collapse(_ i: Int) {
        guard canCollapse(i) else { return }
        panes[i].collapsed = true
        if focus == i, let next = panes.indices.filter({ !panes[$0].collapsed }).max(by: { panes[$0].pressed < panes[$1].pressed }) {
            press(next)
        }
    }

    /// The focus goes to the pane pressed most recently that isn't folded by hand; were every pane left folded, that
    /// pane opens, since the focus never folds.
    private mutating func refocus() {
        let open = panes.indices.filter { !panes[$0].collapsed }
        let pool = open.isEmpty ? Array(panes.indices) : open
        focus = pool.max { panes[$0].pressed < panes[$1].pressed } ?? 0
        panes[focus].collapsed = false
        countFocusNewest()
    }

    // The focus counts as the newest press, as it is after a press: a pane folded by hand may have been pressed
    // since the one the focus falls back to, and `fold` keeps the run where it is only while the focus is the newest.
    private mutating func countFocusNewest() {
        guard panes.indices.contains(where: { $0 != focus && panes[$0].pressed >= panes[focus].pressed }) else { return }
        clock += 1
        panes[focus].pressed = clock
    }

    /// The focused pane goes to `link`, as a click in it does. A new address keeps no note mode from the old one.
    public mutating func open(_ link: AppLink) { open(link, in: focus) }

    /// Pane `i` goes to `link`, as its own history moves it.
    public mutating func open(_ link: AppLink, in i: Int) {
        guard panes.indices.contains(i) else { return }
        if panes[i].link.withoutAnchor != link.withoutAnchor { panes[i].noteMode = nil }
        panes[i].link = link
    }

    public mutating func show(_ mode: NoteViewMode, in i: Int) {
        if panes.indices.contains(i) { panes[i].noteMode = mode }
    }

    /// "옆 칸에 열기". A pane already showing the target takes it; else a new pane opens right of the focused one and
    /// takes half its width. Either way the pane showing it is pressed.
    public mutating func openBeside(_ link: AppLink) {
        if let i = panes.firstIndex(where: { $0.link.withoutAnchor == link.withoutAnchor }) {
            panes[i].link = link
            return press(i)
        }
        let half = panes[focus].share / 2
        panes[focus].share = half
        panes.insert(Pane(link: link, share: half, pressed: clock), at: focus + 1)
        press(focus + 1)
    }

    /// "옆 칸으로 합치기" (2026-11-09 사용자): another tab's panes join these before pane `index` (0 the leading edge,
    /// `panes.count` the trailing one), keeping their order, note modes and folds. Together they take the share of
    /// the row their count is of all the panes, between themselves as they had it, so a tab of one joining a tab
    /// of one halves the row. The focus goes to the pane that was focused in the other tab, which is what was being
    /// looked at there; its panes count as pressed after these, in the order they were. All of them join, since a
    /// tab's panes are one layout and a pane left behind would be closed without being asked.
    public mutating func merge(_ other: PaneLayout, at index: Int) {
        let at = min(max(index, 0), panes.count)
        let joining = Double(other.panes.count) / Double(panes.count + other.panes.count)
        for i in panes.indices { panes[i].share *= 1 - joining }

        var added = other.panes
        for (rank, j) in other.panes.indices.sorted(by: { other.panes[$0].pressed < other.panes[$1].pressed }).enumerated() {
            added[j].pressed = clock + 1 + rank
        }
        for j in added.indices { added[j].share *= joining }

        clock += added.count
        panes.insert(contentsOf: added, at: at)
        press(at + other.focus)
    }

    /// False, and nothing closed, for the last pane. The width goes to the pane on the left (on the right for the
    /// first), which stood beside it; the focus goes to the pane pressed most recently.
    @discardableResult
    public mutating func close(_ i: Int) -> Bool {
        guard panes.count > 1, panes.indices.contains(i) else { return false }
        let share = panes.remove(at: i).share
        panes[i > 0 ? i - 1 : 0].share += share
        refocus()
        return true
    }

    /// "좌우 바꾸기": two panes trade places with their widths; the focus stays on the pane it was on.
    public mutating func swap(_ i: Int, _ j: Int) {
        guard panes.indices.contains(i), panes.indices.contains(j), i != j else { return }
        panes.swapAt(i, j)
        if focus == i { focus = j } else if focus == j { focus = i }
    }

    /// Drags the divider after pane `divider` to `fraction` of the two panes beside it, from the left one's leading
    /// edge to the right one's trailing edge. The other panes keep their widths.
    public mutating func resize(divider d: Int, to fraction: Double) {
        guard d >= 0, d + 1 < panes.count, fraction.isFinite else { return }
        let pair = panes[d].share + panes[d + 1].share
        guard pair >= 2 * Self.minShare else { return }
        let left = min(max(pair * fraction, Self.minShare), pair - Self.minShare)
        panes[d].share = left
        panes[d + 1].share = pair - left
    }

    /// A double click on any divider: every pane takes the same share, however many there are (2026-11-08 사용자).
    public mutating func even() {
        for i in panes.indices { panes[i].share = 1 / Double(panes.count) }
    }

    /// Only the panes `keep` takes, in their order, their shares made whole again: a remembered layout without the
    /// panes whose item is gone. The focus stays where it was if that pane is kept, else goes to the pane pressed
    /// most recently. Nil when none is kept.
    public func keeping(_ keep: (Int) -> Bool) -> PaneLayout? {
        let kept = panes.indices.filter(keep)
        guard !kept.isEmpty else { return nil }
        var copy = self
        copy.panes = kept.map { panes[$0] }
        let total = copy.panes.map(\.share).reduce(0, +)
        for i in copy.panes.indices { copy.panes[i].share /= total }
        if let focused = kept.firstIndex(of: focus) {
            copy.focus = focused
            copy.panes[focused].collapsed = false
        } else {
            copy.refocus()
        }
        return copy
    }

    /// The class this layout is laid out for (#62): the one session its notes and recordings belong to, in any of
    /// `files`. Nil when they belong to none, or to more than one, so a tab showing two classes' notes is neither's.
    public func session(in files: [CourseFile]) -> UUID? {
        let sessions = Set(panes.compactMap { pane in files.lazy.compactMap { $0.session(holding: pane.link) }.first })
        return sessions.count == 1 ? sessions.first : nil
    }

    // MARK: Fit

    /// How the row draws the panes in a width (2026-11-12 사용자): a run of them in place, the focus among them, each
    /// open or, folded by hand, a strip; and the rest folded into a bundle at either end, every pane left of the run in
    /// the left one and every pane right of it in the right. A bundle is one strip however many it holds, so any number
    /// of panes fits one open pane and two strips, and the panes keep their order on the row.
    public struct Fold: Hashable, Sendable {
        public enum Look: Hashable, Sendable {
            case open
            /// Folded by hand, in its place in the run.
            case strip
            /// The strip of a bundle, holding these panes in order: drawn in the place of the one nearest the run, so a
            /// bundle of one is that pane's own strip, and a pane leaving the run steps into it.
            case bundle([Int])
            /// In a bundle, drawn by its strip.
            case hidden
        }

        public let count: Int
        public let run: ClosedRange<Int>
        /// The run's panes folded by hand.
        public let strips: Set<Int>

        /// Every pane in place, as a row not yet measured is drawn.
        init(_ layout: PaneLayout) {
            self.init(count: layout.panes.count, run: 0...(layout.panes.count - 1), collapsed: layout.collapsed)
        }

        init(count: Int, run: ClosedRange<Int>, collapsed: Set<Int>) {
            self.count = count
            self.run = run
            strips = collapsed.filter { run.contains($0) }
        }

        public var left: [Int] { Array(0..<run.lowerBound) }
        public var right: [Int] { Array((run.upperBound + 1)..<count) }
        public var open: [Int] { run.filter { !strips.contains($0) } }
        /// Every pane not drawn open.
        public var folded: Set<Int> { Set(0..<count).subtracting(open) }

        public func look(_ i: Int) -> Look {
            if run.contains(i) { return strips.contains(i) ? .strip : .open }
            if i == run.lowerBound - 1 { return .bundle(left) }
            if i == run.upperBound + 1 { return .bundle(right) }
            return .hidden
        }

        /// The gap after each pane but the last: `gap` between two drawn side by side, none beside a pane in a bundle.
        public func gaps(_ gap: Double) -> [Double] {
            let first = max(run.lowerBound - 1, 0), last = min(run.upperBound + 1, count - 1)
            return (0..<max(count - 1, 0)).map { $0 >= first && $0 < last ? gap : 0 }
        }
    }

    public struct Fit: Equatable, Sendable {
        public var fold: Fold
        public var widths: [Double]
        public var gaps: [Double]
        public var folded: Set<Int> { fold.folded }
    }

    public func fit(room: Double, minWidth: Double, strip: Double, gap: Double) -> Fit {
        let folding = self.fold(room: room, minWidth: minWidth, strip: strip, gap: gap)
        return Fit(
            fold: folding, widths: widths(room: room, fold: folding, minWidth: minWidth, strip: strip, gap: gap), gaps: folding.gaps(gap))
    }

    /// Every pane stays in place while they fit, open ones at `minWidth` and the rest at `strip`, with `gap` between.
    /// Else the run, from the whole row, gives up whichever of its end panes was pressed longer ago, never the focus,
    /// to the bundle on that side, until it fits or the focus is left alone (2026-11-12 사용자). A pane folded by hand
    /// at an end beside a bundle goes in with it: in place it costs a strip the bundle saves.
    ///
    /// The run hangs on the width and the presses alone, not on what was drawn before, so a window narrowed and widened
    /// again is laid out as it was. Pressing a pane in a bundle still moves the run no further than it must: the press
    /// makes it the newest, so the peeling that left it out now stops with it at the run's end.
    public func fold(room: Double, minWidth: Double, strip: Double, gap: Double) -> Fold {
        let n = panes.count
        var lo = 0, hi = n - 1
        func cost() -> Double {
            let drawn = hi - lo + 1 + (lo > 0 ? 1 : 0) + (hi < n - 1 ? 1 : 0)
            let open = (lo...hi).filter { !panes[$0].collapsed }.count
            return Double(open) * minWidth + Double(drawn - open) * strip + Double(drawn - 1) * gap
        }
        while lo < hi, cost() > room {
            if hi == focus || (lo != focus && panes[lo].pressed < panes[hi].pressed) { lo += 1 } else { hi -= 1 }
            while lo > 0, lo < focus, panes[lo].collapsed { lo += 1 }
            while hi < n - 1, hi > focus, panes[hi].collapsed { hi -= 1 }
        }
        return Fold(count: n, run: lo...hi, collapsed: collapsed)
    }

    /// Each pane's width in `room` as `fold` draws them, the gaps taken out: a strip and a bundle `strip`, a pane in a
    /// bundle nothing, and the open panes what is left by their shares, none below `minWidth`; a lone open pane takes
    /// what there is, even less. A fold made for another count of panes is read as every pane in place.
    public func widths(room: Double, fold: Fold, minWidth: Double, strip: Double, gap: Double = 0) -> [Double] {
        let drawn = fold.count == panes.count ? fold : Fold(self)
        var widths = panes.indices.map { i -> Double in
            switch drawn.look(i) {
            case .strip, .bundle: strip
            case .open, .hidden: 0
            }
        }

        var left = max(0, room - widths.reduce(0, +) - drawn.gaps(gap).reduce(0, +))
        // Shares first; a pane they'd leave under `minWidth` is held there and the rest share again.
        var sharing = drawn.open
        while !sharing.isEmpty {
            let total = sharing.map { panes[$0].share }.reduce(0, +)
            let under = sharing.filter { left * panes[$0].share / total < minWidth }
            if under.isEmpty || sharing.count == 1 {
                for i in sharing { widths[i] = max(0, sharing.count == 1 ? left : left * panes[i].share / total) }
                break
            }
            for i in under {
                widths[i] = minWidth
                left -= minWidth
            }
            sharing.removeAll(where: under.contains)
        }
        return widths
    }

    public var unfolded: Fold { Fold(self) }
}

extension PaneLayout: Codable {
    private enum CodingKeys: String, CodingKey { case panes, focus }
    private enum PaneKeys: String, CodingKey { case link, share, noteMode, collapsed, pressed }

    // Links are written as their `folio://` text, the same form a note or the CLI writes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var list = try c.nestedUnkeyedContainer(forKey: .panes)
        var panes: [Pane] = []
        while !list.isAtEnd {
            let p = try list.nestedContainer(keyedBy: PaneKeys.self)
            let text = try p.decode(String.self, forKey: .link)
            guard let link = AppLink(string: text) else {
                throw DecodingError.dataCorruptedError(forKey: .link, in: p, debugDescription: "Not a folio link: \(text)")
            }
            panes.append(
                Pane(
                    link: link, share: try p.decode(Double.self, forKey: .share),
                    noteMode: try p.decodeIfPresent(NoteViewMode.self, forKey: .noteMode),
                    collapsed: try p.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false,
                    pressed: try p.decode(Int.self, forKey: .pressed)))
        }

        guard !panes.isEmpty, panes.allSatisfy({ $0.share > 0 && $0.share.isFinite }) else {
            throw DecodingError.dataCorruptedError(forKey: .panes, in: c, debugDescription: "No panes, or a share that isn't positive")
        }

        let total = panes.map(\.share).reduce(0, +)
        for i in panes.indices { panes[i].share /= total }
        self.panes = panes
        focus = min(max(try c.decode(Int.self, forKey: .focus), 0), panes.count - 1)
        clock = panes.map(\.pressed).max() ?? 0
        if self.panes[focus].collapsed { refocus() } else { countFocusNewest() }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var list = c.nestedUnkeyedContainer(forKey: .panes)
        for pane in panes {
            var p = list.nestedContainer(keyedBy: PaneKeys.self)
            try p.encode(pane.link.string, forKey: .link)
            try p.encode(pane.share, forKey: .share)
            try p.encodeIfPresent(pane.noteMode, forKey: .noteMode)
            if pane.collapsed { try p.encode(true, forKey: .collapsed) }
            try p.encode(pane.pressed, forKey: .pressed)
        }
        try c.encode(focus, forKey: .focus)
    }
}

private extension PaneLayout {
    var nilIfAlone: PaneLayout? { panes.count > 1 ? self : nil }
}

extension CourseFile {
    /// The class `link` belongs to, for a layout to be remembered by: a class's rough or review note, or its
    /// recording. Not the class's own link, which opens the course's list of classes.
    public func session(holding link: AppLink) -> UUID? {
        guard let id = link.id else { return nil }
        switch link.kind {
        case .note: return sessions.first { $0.roughNoteId == id || $0.reviewNoteId == id }?.id
        case .recording: return recordings.first { $0.id == id }?.sessionId
        case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester, .course, .session, .unit,
            .material, .assignment, .exam, .card, .problemSet, .person:
            return nil
        }
    }
}

/// What one device remembers of how things were last shown: each session's layout and each note's view mode. Kept
/// on the device, not in the GIST folder: its widths fit the device's screen, it changes with every drag and click,
/// and losing it costs only the default layout.
public struct PaneMemory: Codable, Hashable, Sendable {
    /// Per kind. The ones used longest ago go first, so the memory doesn't grow with every note ever opened.
    public static let capacity = 300

    private struct Kept<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        var value: Value
        var used: Date
    }

    // String keys, so the JSON is an object rather than Codable's alternating array for UUID keys.
    private var layouts: [String: Kept<PaneLayout>] = [:]
    private var noteModes: [String: Kept<NoteViewMode>] = [:]

    public init() {}

    public func layout(session: UUID) -> PaneLayout? { layouts[session.uuidString]?.value }

    public mutating func remember(_ layout: PaneLayout, session: UUID, at date: Date) {
        layouts[session.uuidString] = Kept(value: layout, used: date)
        Self.trim(&layouts)
    }

    /// What opening `link` turns a tab of one pane into: the session's layout as it was last left, with `link` in its
    /// pane and that pane focused (2026-11-11). Only a layout that has `link` in it, since one without it is not the
    /// one being opened, and of more than one pane, which is what the tab is already. Every pane comes back, a layout
    /// left on a wider screen too: the row folds what it has no room for.
    public func restoring(_ link: AppLink, session: UUID) -> PaneLayout? {
        guard var saved = layout(session: session),
            let i = saved.panes.firstIndex(where: { $0.link.withoutAnchor == link.withoutAnchor })
        else { return nil }
        saved.open(link, in: i)
        saved.press(i)
        return saved.nilIfAlone
    }

    /// The session's layout for a class that starts again (its pages opened side by side, #391), in place of the
    /// preset; nil without one of more than one pane.
    public func starting(session: UUID) -> PaneLayout? {
        layout(session: session)?.nilIfAlone
    }

    /// The mode a note (or a text file) was last left in: in the session's layout when opened there, else wherever it
    /// was opened.
    public func noteMode(note: UUID, session: UUID? = nil) -> NoteViewMode? {
        if let session, let layout = layout(session: session),
            let pane = layout.panes.first(where: { $0.link.id == note }), let mode = pane.noteMode
        {
            return mode
        }
        return noteModes[note.uuidString]?.value
    }

    public mutating func remember(_ mode: NoteViewMode, note: UUID, at date: Date) {
        noteModes[note.uuidString] = Kept(value: mode, used: date)
        Self.trim(&noteModes)
    }

    public var count: (layouts: Int, noteModes: Int) { (layouts.count, noteModes.count) }

    private static func trim<V>(_ kept: inout [String: Kept<V>]) {
        guard kept.count > capacity else { return }
        for key in kept.sorted(by: { ($0.value.used, $0.key) < ($1.value.used, $1.key) }).prefix(kept.count - capacity).map(\.key) {
            kept[key] = nil
        }
    }
}
