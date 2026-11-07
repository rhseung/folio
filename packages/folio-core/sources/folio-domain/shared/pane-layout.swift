import Foundation

/// How a note pane shows its note: the preview, the source beside the preview, or the source.
public enum NoteViewMode: String, Codable, Sendable, CaseIterable {
    case read, split, write
}

/// The panes of one tab, left to right (#62). Each pane draws one address (#43) and takes its share of the width.
/// A pane never leaves the layout because the window is narrow: `fit` folds it into a strip instead.
public struct PaneLayout: Hashable, Sendable {
    public enum Device: Sendable {
        case mac, pad

        public var maxPanes: Int {
            switch self {
            case .mac: 3
            case .pad: 2
            }
        }
    }

    public struct Pane: Hashable, Sendable {
        public var link: AppLink
        public fileprivate(set) var share: Double
        /// How a note shown here is shown. It travels with the layout, so a session's layout brings its note back the
        /// way it was left.
        public var noteMode: NoteViewMode?
        // The layout's clock when this pane was last pressed. A tick, not a date: two presses in the same instant
        // must still order, and a restored layout must not fold by when the device was last used.
        fileprivate var pressed: Int

        fileprivate init(link: AppLink, share: Double, noteMode: NoteViewMode? = nil, pressed: Int) {
            self.link = link
            self.share = share
            self.noteMode = noteMode
            self.pressed = pressed
        }
    }

    /// The smallest share a drag leaves a pane, so a divider can't swallow a pane whole; folding is `fit`'s job.
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

    /// The first `limit` links, focused on the first. Shares that don't fit the links (missing, or not all positive)
    /// fall back to even ones. Nil without a link.
    public init?(links: [AppLink], shares: [Double]? = nil, limit: Int) {
        let links = Array(links.prefix(max(1, limit)))
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

    public mutating func press(_ i: Int) {
        guard panes.indices.contains(i) else { return }
        clock += 1
        panes[i].pressed = clock
        focus = i
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

    /// "옆 칸에 열기". A pane already showing the target takes it. Below `limit` a new pane opens right of the focused
    /// one and takes half its width; at `limit` the pane pressed longest ago shows it instead, since the panes in use
    /// are the ones to keep. Either way the pane showing it is pressed.
    public mutating func openBeside(_ link: AppLink, limit: Int) {
        if let i = panes.firstIndex(where: { $0.link.withoutAnchor == link.withoutAnchor }) {
            panes[i].link = link
            return press(i)
        }
        if panes.count < limit {
            let half = panes[focus].share / 2
            panes[focus].share = half
            panes.insert(Pane(link: link, share: half, pressed: clock), at: focus + 1)
            return press(focus + 1)
        }
        guard let oldest = panes.indices.filter({ $0 != focus }).min(by: { panes[$0].pressed < panes[$1].pressed }) else {
            return open(link)
        }
        panes[oldest].link = link
        panes[oldest].noteMode = nil
        press(oldest)
    }

    /// False, and nothing closed, for the last pane. The width goes to the pane on the left (on the right for the
    /// first), which stood beside it; the focus goes to the pane pressed most recently.
    @discardableResult
    public mutating func close(_ i: Int) -> Bool {
        guard panes.count > 1, panes.indices.contains(i) else { return false }
        let share = panes.remove(at: i).share
        panes[i > 0 ? i - 1 : 0].share += share
        focus = panes.indices.max { panes[$0].pressed < panes[$1].pressed } ?? 0
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

    /// What a layout from another device, or from before the limit changed, keeps here: the panes pressed most
    /// recently, in their order, their shares made whole again.
    public func limited(to limit: Int) -> PaneLayout {
        guard panes.count > max(1, limit) else { return self }
        let kept = Set(panes.indices.sorted { panes[$0].pressed > panes[$1].pressed }.prefix(max(1, limit)))
        var copy = self
        copy.panes = panes.indices.filter(kept.contains).map { panes[$0] }
        let total = copy.panes.map(\.share).reduce(0, +)
        for i in copy.panes.indices { copy.panes[i].share /= total }
        copy.focus = copy.panes.indices.max { copy.panes[$0].pressed < copy.panes[$1].pressed } ?? 0
        return copy
    }

    // MARK: Fit

    /// Which panes fold to strips and how wide each is drawn.
    public struct Fit: Equatable, Sendable {
        public var folded: Set<Int>
        public var widths: [Double]
    }

    /// Keeps open as many panes as fit at `minWidth` beside the others' strips and folds the rest, the panes pressed
    /// longest ago first and never the focused one. Pressing a strip (`press`) unfolds it and folds another in its
    /// place. Open panes split what the strips and gaps leave by their shares, none below `minWidth`; a lone open
    /// pane takes what there is, even less.
    public func fit(room: Double, minWidth: Double, strip: Double, gap: Double) -> Fit {
        let folded = folded(open: Self.openCount(panes.count, room: room, minWidth: minWidth, strip: strip, gap: gap))
        return Fit(folded: folded, widths: widths(room: room, folded: folded, minWidth: minWidth, strip: strip, gap: gap))
    }

    /// How many of `count` panes stay open in `room`: as many as fit at `minWidth` beside the others' strips, and
    /// always one. It hangs on the width and the count alone, so a window resized between two counts asks for nothing
    /// else.
    public static func openCount(_ count: Int, room: Double, minWidth: Double, strip: Double, gap: Double) -> Int {
        var open = count
        while open > 1, Double(open) * minWidth + Double(count - open) * strip + Double(count - 1) * gap > room { open -= 1 }
        return open
    }

    /// The panes folded when `open` of them stay open: the ones pressed longest ago, never the focused one.
    public func folded(open: Int) -> Set<Int> {
        let byAge = panes.indices.filter { $0 != focus }.sorted { panes[$0].pressed < panes[$1].pressed }
        return Set(byAge.prefix(max(0, panes.count - max(1, open))))
    }

    /// Each pane's width in `room`, the gaps between them taken out: `strip` for the folded ones, and the rest by
    /// their shares, none below `minWidth`; a lone open pane takes what there is, even less.
    public func widths(room: Double, folded: Set<Int>, minWidth: Double, strip: Double, gap: Double = 0) -> [Double] {
        let n = panes.count
        var widths = panes.indices.map { folded.contains($0) ? strip : 0 }
        var left = max(0, room - Double(folded.count) * strip - Double(n - 1) * gap)
        // Shares first; a pane they'd leave under `minWidth` is held there and the rest share again.
        var sharing = panes.indices.filter { !folded.contains($0) }
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
}

extension PaneLayout: Codable {
    private enum CodingKeys: String, CodingKey { case panes, focus }
    private enum PaneKeys: String, CodingKey { case link, share, noteMode, pressed }

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
            panes.append(Pane(link: link, share: try p.decode(Double.self, forKey: .share),
                              noteMode: try p.decodeIfPresent(NoteViewMode.self, forKey: .noteMode),
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
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var list = c.nestedUnkeyedContainer(forKey: .panes)
        for pane in panes {
            var p = list.nestedContainer(keyedBy: PaneKeys.self)
            try p.encode(pane.link.string, forKey: .link)
            try p.encode(pane.share, forKey: .share)
            try p.encodeIfPresent(pane.noteMode, forKey: .noteMode)
            try p.encode(pane.pressed, forKey: .pressed)
        }
        try c.encode(focus, forKey: .focus)
    }
}

/// A named layout to switch to (#62, #64): which kinds of thing go in which pane, and how wide. The app names the
/// built-in ones from its string catalog by `id`.
public struct PanePreset: Hashable, Sendable, Codable, Identifiable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        /// The session's lecture file, at its first page.
        case lecture
        /// The note written in class.
        case classNote
        case reviewNote
        /// The course's quiz.
        case quiz
        /// A problem sheet and the canvas to solve it on. Neither has an address from a session yet, so a preset
        /// opened from a session leaves them out.
        case problems, canvas
    }

    public var id: String
    public var roles: [Role]
    public var shares: [Double]

    public init(id: String, roles: [Role], shares: [Double]) {
        self.id = id
        self.roles = roles
        self.shares = shares
    }

    public static let inClass = PanePreset(id: "in-class", roles: [.lecture, .classNote], shares: [0.55, 0.45])
    public static let concepts = PanePreset(id: "concepts", roles: [.lecture, .quiz], shares: [0.6, 0.4])
    public static let problems = PanePreset(id: "problems", roles: [.problems, .canvas], shares: [0.5, 0.5])
    /// Opened for a class's review and a unit's review (#146).
    public static let review = PanePreset(id: "review", roles: [.reviewNote, .quiz], shares: [0.6, 0.4])
    public static let builtIn = [inClass, concepts, problems, review]

    public func link(for role: Role, session: Session, course: UUID) -> AppLink? {
        switch role {
        case .lecture:
            session.materials.first.map { AppLink(.material, $0.materialId, anchor: $0.firstPage.map(AppLink.Anchor.page)) }
        case .classNote: session.roughNoteId.map { AppLink(.note, $0) }
        case .reviewNote: session.reviewNoteId.map { AppLink(.note, $0) }
        case .quiz: .course(course, page: .quiz)
        case .problems, .canvas: nil
        }
    }

    /// The preset filled in for a session, without the roles it has nothing for. Nil when it has none.
    public func layout(session: Session, course: UUID, limit: Int) -> PaneLayout? {
        let filled = zip(roles, shares).compactMap { role, share in link(for: role, session: session, course: course).map { ($0, share) } }
        return PaneLayout(links: filled.map(\.0), shares: filled.map(\.1), limit: limit)
    }

    /// The preset the layout is, filled in for the session, so a tab can go by the preset's name. Pages and blocks
    /// don't count, nor widths: a lecture read further on is still the same layout.
    public static func matching(_ layout: PaneLayout, session: Session, course: UUID, limit: Int) -> PanePreset? {
        builtIn.first { preset in
            guard let filled = preset.layout(session: session, course: course, limit: limit) else { return false }
            return filled.links.map(\.withoutAnchor) == layout.links.map(\.withoutAnchor)
        }
    }
}

/// What one device remembers of how things were last shown: each session's layout and each note's view mode. Kept
/// on the device, not in the GIST folder: it fits the device's screen (a Mac holds three panes, an iPad two), changes
/// with every drag and click, and losing it costs only the default layout.
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

    /// The mode a note was last left in: in the session's layout when opened there, else wherever it was opened.
    public func noteMode(note: UUID, session: UUID? = nil) -> NoteViewMode? {
        if let session, let layout = layout(session: session),
           let pane = layout.panes.first(where: { $0.link.kind == .note && $0.link.id == note }), let mode = pane.noteMode {
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
