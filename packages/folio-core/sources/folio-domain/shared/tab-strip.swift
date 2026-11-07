import Foundation

/// The tabs of one window, in order, and the one in front. A value, so the window's tabs can be saved and restored
/// (#46); what each tab shows is kept by the window under the tab's ID.
public struct TabStrip<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var tabs: [ID]
    public private(set) var selected: ID

    public init(_ first: ID) {
        tabs = [first]
        selected = first
    }

    /// Nil when `selected` isn't one of `tabs`, or a tab is there twice.
    public init?(tabs: [ID], selected: ID) {
        guard tabs.contains(selected), Set(tabs).count == tabs.count else { return nil }
        self.tabs = tabs
        self.selected = selected
    }

    public var selectedIndex: Int { tabs.firstIndex(of: selected) ?? 0 }

    /// A new tab comes to the front. One a link opened goes right after the tab it came from, as in Safari and
    /// Chrome, so it sits beside what led to it; a blank one (⌘T, +) goes last.
    public mutating func open(_ id: ID, afterSelected: Bool = false) {
        guard !tabs.contains(id) else { return select(id) }
        tabs.insert(id, at: afterSelected ? selectedIndex + 1 : tabs.count)
        selected = id
    }

    public mutating func select(_ id: ID) {
        if tabs.contains(id) { selected = id }
    }

    /// ⌘1 to ⌘8: the tab at that place from the left; past the last tab, nothing. ⌘9 is the last tab, however many,
    /// as in Safari and Chrome.
    public mutating func select(number n: Int) {
        if n == 9, let last = tabs.last { return selected = last }
        if tabs.indices.contains(n - 1) { selected = tabs[n - 1] }
    }

    /// ⌃Tab and ⌃⇧Tab, around from the last tab to the first.
    public mutating func selectNext() { selected = tabs[(selectedIndex + 1) % tabs.count] }
    public mutating func selectPrevious() { selected = tabs[(selectedIndex + tabs.count - 1) % tabs.count] }

    /// False, and nothing closed, for the last tab: closing it closes the window. Closing the tab in front brings the
    /// one after it forward, or the one before when it was last, so the tab under the pointer is the next to close.
    @discardableResult
    public mutating func close(_ id: ID) -> Bool {
        guard tabs.count > 1, let i = tabs.firstIndex(of: id) else { return false }
        tabs.remove(at: i)
        if selected == id { selected = tabs[min(i, tabs.count - 1)] }
        return true
    }

    /// Keeps `id` alone, in front.
    public mutating func closeOthers(than id: ID) {
        guard tabs.contains(id) else { return }
        tabs = [id]
        selected = id
    }

    /// Puts `id` at `index` among the tabs, as a drag drops it there.
    public mutating func move(_ id: ID, to index: Int) {
        guard let i = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: i)
        tabs.insert(id, at: max(0, min(index, tabs.count)))
    }
}

/// How the tabs share the toolbar row. The tab in front shows the whole place it is at and is never narrowed for the
/// others: they give way first, down to their icons, and then into a "+n" menu at the row's end.
public enum TabFit {
    public struct Layout: Equatable, Sendable {
        /// The other tabs show only their icons.
        public var iconsOnly: Bool
        /// How many of the other tabs, from the left, are in the row; the rest are in the menu.
        public var shown: Int
        public var hidden: Int

        public init(iconsOnly: Bool, shown: Int, hidden: Int) {
            self.iconsOnly = iconsOnly
            self.shown = shown
            self.hidden = hidden
        }
    }

    /// The space before the first tab, after the buttons ending at `after`, so the first tab's capsule starts at the
    /// content panel's leading edge, `panelEdge`, and lines up with it. The capsule pads its own contents, so the
    /// `Space.l` inset the bare breadcrumb took would leave the capsule short of the edge. When the edge is under the
    /// buttons or near them (the sidebar folded), the tabs keep `gap` after them instead.
    public static func lead(panelEdge: Double, after: Double, gap: Double) -> Double {
        max(gap, panelEdge - after)
    }

    /// - Parameters:
    ///   - room: the row's width for the tabs and the menu.
    ///   - selected: the tab in front, at its full width.
    ///   - others: every other tab at its full width, left to right.
    ///   - icon: an other tab with only its icon.
    ///   - gap: between two neighbors in the row.
    ///   - more: the menu of the tabs that don't fit.
    public static func layout(room: Double, selected: Double, others: [Double], icon: Double, gap: Double, more: Double) -> Layout {
        let n = others.count
        guard n > 0 else { return Layout(iconsOnly: false, shown: 0, hidden: 0) }
        func width(_ tabs: Double, count: Int, menu: Bool) -> Double {
            let items = 1 + count + (menu ? 1 : 0)
            return selected + tabs + (menu ? more : 0) + gap * Double(items - 1)
        }
        if width(others.reduce(0, +), count: n, menu: false) <= room { return Layout(iconsOnly: false, shown: n, hidden: 0) }
        if width(icon * Double(n), count: n, menu: false) <= room { return Layout(iconsOnly: true, shown: n, hidden: 0) }
        // The menu stays even when no icon fits beside the tab in front, which then folds its own trail.
        var shown = n - 1
        while shown > 0, width(icon * Double(shown), count: shown, menu: true) > room { shown -= 1 }
        return Layout(iconsOnly: true, shown: shown, hidden: n - shown)
    }

    /// The width the tab in front's trail is held to, or nil while the tab fits at its own width (`selected`, its
    /// `chrome` included). Nil for every width with room to spare, so a window resized there leaves the tabs alone.
    /// Held, it takes what the row leaves, however little: a strip wider than the row pushes the toolbar's own items
    /// (the search field and the buttons) into its overflow menu.
    public static func trail(room: Double, selected: Double, others: [Double], layout: Layout, icon: Double, gap: Double,
                             more: Double, chrome: Double) -> Double? {
        let rest = room - beside(others, layout: layout, icon: icon, gap: gap, more: more) - chrome
        return selected <= rest + chrome ? nil : max(0, rest)
    }

    /// What the strip takes: the tab in front (held to `trail` with its `chrome`, else at its own width), the tabs
    /// shown beside it and the menu, with the gaps between them. No more than `room` whenever the tab in front's
    /// capsule and the menu fit in it at all.
    public static func width(selected: Double, others: [Double], layout: Layout, trail: Double?, icon: Double, gap: Double,
                             more: Double, chrome: Double) -> Double {
        (trail.map { $0 + chrome } ?? selected) + beside(others, layout: layout, icon: icon, gap: gap, more: more)
    }

    /// Before the new-tab button after the last capsule: its bare glyph, centered in a button `button` wide, sits
    /// `gap` after it, as the capsules sit among themselves. At the plain gap the button's margin around the glyph
    /// read as a wider gap. Negative when that margin is wider than `gap`: the button's hit area then reaches under
    /// the capsule's edge.
    public static func newTabSpacing(gap: Double, button: Double, glyph: Double) -> Double {
        gap - (button - glyph) / 2
    }

    /// The tabs beside the one in front and the menu, each with the gap before it.
    private static func beside(_ others: [Double], layout: Layout, icon: Double, gap: Double, more: Double) -> Double {
        let shown = others.prefix(layout.shown)
        let tabs = layout.iconsOnly ? icon * Double(shown.count) : shown.reduce(0, +)
        return tabs + gap * Double(shown.count) + (layout.hidden > 0 ? more + gap : 0)
    }
}

/// Which tabs keep their screens alive behind the one in front, as Safari and Chrome keep recent tabs and let the rest
/// go: a kept tab comes back as it was (scroll, open note and its mode, caret), a dropped one is drawn again from its
/// address when it is next in front.
public enum TabKeep {
    public struct Policy: Equatable, Sendable {
        /// Tabs kept behind the one in front, the most recently in front first.
        public var limit: Int
        /// A tab behind for longer than this is dropped.
        public var idle: TimeInterval

        public init(limit: Int, idle: TimeInterval) {
            self.limit = limit
            self.idle = idle
        }
    }

    /// The tabs whose screens stay alive. The tab in front always does; behind it, only tabs alive already (a dropped
    /// tab isn't brought back until it is in front), the `limit` most recently in front, each in front within `idle`.
    /// Under memory pressure only the tab in front is kept, and the playing ones.
    ///
    /// - Parameters:
    ///   - alive: the tabs whose screens are alive now.
    ///   - left: when each tab last went behind another. A tab alive without one is treated as just left.
    ///   - playing: tabs playing a recording. Dropping one would stop what is being listened to, so they stay however
    ///     long or under whatever pressure, outside the `limit` the others share (#317).
    public static func alive<ID: Hashable>(selected: ID, alive: Set<ID>, left: [ID: Date], now: Date, policy: Policy,
                                          pressure: Bool = false, playing: Set<ID> = []) -> Set<ID> {
        let playing = playing.intersection(alive).union([selected])
        guard !pressure else { return playing }
        let behind = alive.subtracting(playing)
            .map { (id: $0, left: left[$0] ?? now) }
            .filter { now.timeIntervalSince($0.left) < policy.idle }
            .sorted { $0.left > $1.left }
            .prefix(max(0, policy.limit))
        return Set(behind.map(\.id)).union(playing)
    }
}
