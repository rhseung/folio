import Foundation

public enum NoteViewMode: String, Codable, Sendable, CaseIterable {
    case read, split, write
}

// 창이 좁아도 칸을 배치에서 빼거나 새 탭으로 떼지 않고, `fold`가 줄 끝의 묶음에 넣는다. 폭 때문에 나눈 탭은 폭이
// 돌아와도 다시 합쳐지지 않으므로, 창 크기를 바꾸거나 iPad를 돌릴 때마다 배치가 바뀌기 때문이다.
public struct PaneLayout: Hashable, Sendable {
    public struct Pane: Hashable, Sendable {
        public var link: AppLink
        public fileprivate(set) var share: Double
        public var noteMode: NoteViewMode?
        public fileprivate(set) var collapsed = false
        // 날짜가 아니라 배치의 시계 값이다. 같은 순간에 두 번 눌러도 순서가 있어야 하고, 되돌린 배치가 기기를 마지막으로
        // 쓴 시각에 따라 접히면 안 된다.
        fileprivate var pressed: Int

        fileprivate init(link: AppLink, share: Double, noteMode: NoteViewMode? = nil, collapsed: Bool = false, pressed: Int) {
            self.link = link
            self.share = share
            self.noteMode = noteMode
            self.collapsed = collapsed
            self.pressed = pressed
        }
    }

    public static let minShare = 0.1

    public private(set) var panes: [Pane]
    public private(set) var focus: Int
    private var clock: Int

    public init(_ link: AppLink) {
        panes = [Pane(link: link, share: 1, pressed: 0)]
        focus = 0
        clock = 0
    }

    public init?(links: [AppLink], shares: [Double]? = nil) {
        guard !links.isEmpty else { return nil }
        var shares = shares.map { Array($0.prefix(links.count)) } ?? []
        if shares.count != links.count || shares.contains(where: { !($0 > 0) || !$0.isFinite }) {
            shares = Array(repeating: 1, count: links.count)
        }
        let total = shares.reduce(0, +)
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

    public mutating func press(_ i: Int) {
        guard panes.indices.contains(i) else { return }
        clock += 1
        panes[i].pressed = clock
        panes[i].collapsed = false
        focus = i
    }

    public func canCollapse(_ i: Int) -> Bool {
        panes.indices.contains(i) && !panes[i].collapsed && panes.indices.contains { $0 != i && !panes[$0].collapsed }
    }

    public mutating func collapse(_ i: Int) {
        guard canCollapse(i) else { return }
        panes[i].collapsed = true
        if focus == i, let next = panes.indices.filter({ !panes[$0].collapsed }).max(by: { panes[$0].pressed < panes[$1].pressed }) {
            press(next)
        }
    }

    private mutating func refocus() {
        let open = panes.indices.filter { !panes[$0].collapsed }
        let pool = open.isEmpty ? Array(panes.indices) : open
        focus = pool.max { panes[$0].pressed < panes[$1].pressed } ?? 0
        panes[focus].collapsed = false
        countFocusNewest()
    }

    // 손으로 접은 칸이 포커스가 돌아갈 칸보다 나중에 눌렸을 수 있다. `fold`는 포커스가 가장 최근에 누른 칸일 때만
    // 펼친 칸들을 제자리에 두므로, 누른 뒤와 같이 포커스를 가장 최근에 누른 칸으로 센다.
    private mutating func countFocusNewest() {
        guard panes.indices.contains(where: { $0 != focus && panes[$0].pressed >= panes[focus].pressed }) else { return }
        clock += 1
        panes[focus].pressed = clock
    }

    public mutating func open(_ link: AppLink) { open(link, in: focus) }

    public mutating func open(_ link: AppLink, in i: Int) {
        guard panes.indices.contains(i) else { return }
        if panes[i].link.withoutAnchor != link.withoutAnchor { panes[i].noteMode = nil }
        panes[i].link = link
    }

    public mutating func show(_ mode: NoteViewMode, in i: Int) {
        if panes.indices.contains(i) { panes[i].noteMode = mode }
    }

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

    @discardableResult
    public mutating func close(_ i: Int) -> Bool {
        guard panes.count > 1, panes.indices.contains(i) else { return false }
        let share = panes.remove(at: i).share
        panes[i > 0 ? i - 1 : 0].share += share
        refocus()
        return true
    }

    public mutating func swap(_ i: Int, _ j: Int) {
        guard panes.indices.contains(i), panes.indices.contains(j), i != j else { return }
        panes.swapAt(i, j)
        if focus == i { focus = j } else if focus == j { focus = i }
    }

    public mutating func resize(divider d: Int, to fraction: Double) {
        guard d >= 0, d + 1 < panes.count, fraction.isFinite else { return }
        let pair = panes[d].share + panes[d + 1].share
        guard pair >= 2 * Self.minShare else { return }
        let left = min(max(pair * fraction, Self.minShare), pair - Self.minShare)
        panes[d].share = left
        panes[d + 1].share = pair - left
    }

    public mutating func even() {
        for i in panes.indices { panes[i].share = 1 / Double(panes.count) }
    }

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

    public func session(in files: [CourseFile]) -> UUID? {
        let sessions = Set(panes.compactMap { pane in files.lazy.compactMap { $0.session(holding: pane.link) }.first })
        return sessions.count == 1 ? sessions.first : nil
    }

    // MARK: Fit

    public struct Fold: Hashable, Sendable {
        public enum Look: Hashable, Sendable {
            case open
            case strip
            case bundle([Int])
            case hidden
        }

        public let count: Int
        public let run: ClosedRange<Int>
        public let strips: Set<Int>

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
        public var folded: Set<Int> { Set(0..<count).subtracting(open) }

        public func look(_ i: Int) -> Look {
            if run.contains(i) { return strips.contains(i) ? .strip : .open }
            if i == run.lowerBound - 1 { return .bundle(left) }
            if i == run.upperBound + 1 { return .bundle(right) }
            return .hidden
        }

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

    // 펼친 칸들은 폭과 누른 순서로만 정하고 전에 그린 모양을 보지 않는다. 그래야 창을 좁혔다 다시 넓히면 처음과
    // 같이 배치된다.
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

    public func widths(room: Double, fold: Fold, minWidth: Double, strip: Double, gap: Double = 0) -> [Double] {
        let drawn = fold.count == panes.count ? fold : Fold(self)
        var widths = panes.indices.map { i -> Double in
            switch drawn.look(i) {
            case .strip, .bundle: strip
            case .open, .hidden: 0
            }
        }

        var left = max(0, room - widths.reduce(0, +) - drawn.gaps(gap).reduce(0, +))
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

public struct PaneMemory: Codable, Hashable, Sendable {
    public static let capacity = 300

    private struct Kept<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        var value: Value
        var used: Date
    }

    // UUID 키를 쓰면 Codable이 키와 값이 번갈아 놓인 배열로 쓰므로, 문자열 키를 써서 JSON 객체로 둔다.
    private var layouts: [String: Kept<PaneLayout>] = [:]
    private var noteModes: [String: Kept<NoteViewMode>] = [:]

    public init() {}

    public func layout(session: UUID) -> PaneLayout? { layouts[session.uuidString]?.value }

    public mutating func remember(_ layout: PaneLayout, session: UUID, at date: Date) {
        layouts[session.uuidString] = Kept(value: layout, used: date)
        Self.trim(&layouts)
    }

    public func restoring(_ link: AppLink, session: UUID) -> PaneLayout? {
        guard var saved = layout(session: session),
            let i = saved.panes.firstIndex(where: { $0.link.withoutAnchor == link.withoutAnchor })
        else { return nil }
        saved.open(link, in: i)
        saved.press(i)
        return saved.nilIfAlone
    }

    public func starting(session: UUID) -> PaneLayout? {
        layout(session: session)?.nilIfAlone
    }

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
