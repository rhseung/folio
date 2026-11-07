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

/// How the tabs share the toolbar row (#304, #62). The tab in front shows the whole place its focused pane is at and is
/// the last to give way. As the row runs out, in this order (each step keeps the ones before it):
/// 1. the other tabs drop their names (a single pane's, a layout's preset) and keep their icons;
/// 2. another tab of several panes stacks them into its first pane's icon and "+n";
/// 3. the tab in front's segments other than the focused one keep only their icons;
/// 4. the tabs that still don't fit go into the "+n" menu at the row's end;
/// 5. the focused segment's trail folds its middle (`trail`).
public enum TabFit {
    /// A tab behind the one in front, at each width it can take.
    public struct Other: Equatable, Sendable {
        /// Its icons and its name.
        public var full: Double
        /// Its panes' icons alone, joined.
        public var icons: Double
        /// Its first pane's icon and "+n"; a tab of one pane stays at its icon.
        public var stacked: Double

        public init(full: Double, icons: Double, stacked: Double) {
            self.full = full
            self.icons = icons
            self.stacked = stacked
        }

        /// A tab of one pane: its icon and name, or its icon.
        public init(single full: Double, icon: Double) {
            self.init(full: full, icons: icon, stacked: icon)
        }
    }

    /// The tab in front: its trail, and the rest of its capsule around it (the close button, and with several panes
    /// the other panes' segments), those segments named or as icons (`compactChrome`).
    public struct Front: Equatable, Sendable {
        public var trail: Double
        public var chrome: Double
        public var compactChrome: Double

        public init(trail: Double, chrome: Double, compactChrome: Double? = nil) {
            self.trail = trail
            self.chrome = chrome
            self.compactChrome = compactChrome ?? chrome
        }

        public func chrome(compact: Bool) -> Double { compact ? compactChrome : chrome }
        public func width(compact: Bool) -> Double { trail + chrome(compact: compact) }
    }

    public struct Layout: Equatable, Sendable {
        /// Step 1: the other tabs show only their icons.
        public var iconsOnly: Bool
        /// Step 2: the other tabs of several panes show their first icon and "+n".
        public var stacked: Bool
        /// Step 3: the tab in front's other segments show only their icons.
        public var compactFront: Bool
        /// How many of the other tabs, from the left, are in the row; the rest are in the menu (step 4).
        public var shown: Int
        public var hidden: Int

        public init(iconsOnly: Bool, stacked: Bool = false, compactFront: Bool = false, shown: Int, hidden: Int) {
            self.iconsOnly = iconsOnly
            self.stacked = stacked
            self.compactFront = compactFront
            self.shown = shown
            self.hidden = hidden
        }

        /// How many of steps 1 to 4 the row has taken.
        public var step: Int {
            hidden > 0 ? 4 : compactFront ? 3 : stacked ? 2 : iconsOnly ? 1 : 0
        }

        /// What an other tab takes in this layout.
        public func width(of tab: Other) -> Double {
            !iconsOnly ? tab.full : stacked ? tab.stacked : tab.icons
        }
    }

    /// The space before the first tab, after the buttons ending at `after`, so the first tab's capsule starts at the
    /// content panel's leading edge, `panelEdge`, and lines up with it. The capsule pads its own contents, so the
    /// `Space.l` inset the bare breadcrumb took would leave the capsule short of the edge. When the edge is under the
    /// buttons or near them (the sidebar folded), the tabs keep `gap` after them instead.
    public static func lead(panelEdge: Double, after: Double, gap: Double) -> Double {
        max(gap, panelEdge - after)
    }

    /// The first of steps 0 to 4 whose row fits in `room`.
    /// - Parameters:
    ///   - room: the row's width for the tabs and the menu.
    ///   - front: the tab in front with its whole trail.
    ///   - others: every other tab, left to right.
    ///   - gap: between two neighbors in the row.
    ///   - more: the menu of the tabs that don't fit.
    public static func layout(room: Double, front: Front, others: [Other], gap: Double, more: Double) -> Layout {
        let n = others.count
        let steps = [Layout(iconsOnly: false, shown: n, hidden: 0),
                     Layout(iconsOnly: true, shown: n, hidden: 0),
                     Layout(iconsOnly: true, stacked: true, shown: n, hidden: 0),
                     Layout(iconsOnly: true, stacked: true, compactFront: true, shown: n, hidden: 0)]
        for step in steps where front.width(compact: step.compactFront) + beside(others, layout: step, gap: gap, more: more) <= room {
            return step
        }
        guard n > 0 else { return steps[3] }
        // The menu stays even when no icon fits beside the tab in front, which then folds its own trail.
        var fit = Layout(iconsOnly: true, stacked: true, compactFront: true, shown: n - 1, hidden: 1)
        while fit.shown > 0, front.width(compact: true) + beside(others, layout: fit, gap: gap, more: more) > room {
            fit.shown -= 1
            fit.hidden += 1
        }
        return fit
    }

    /// The width the tab in front's trail is held to, or nil while the tab fits with its own trail. Nil for every
    /// width with room to spare, so a window resized there leaves the tabs alone. Held, it takes what the row leaves,
    /// however little: a strip wider than the row pushes the toolbar's own items (the search field and the buttons)
    /// into its overflow menu.
    public static func trail(room: Double, front: Front, others: [Other], layout: Layout, gap: Double, more: Double) -> Double? {
        let rest = room - beside(others, layout: layout, gap: gap, more: more) - front.chrome(compact: layout.compactFront)
        return front.trail <= rest ? nil : max(0, rest)
    }

    /// What the strip takes: the tab in front (its trail held to `trail`, else its own), the tabs shown beside it and
    /// the menu, with the gaps between them. No more than `room` whenever the tab in front's capsule and the menu fit
    /// in it at all.
    public static func width(front: Front, others: [Other], layout: Layout, trail: Double?, gap: Double, more: Double) -> Double {
        (trail ?? front.trail) + front.chrome(compact: layout.compactFront) + beside(others, layout: layout, gap: gap, more: more)
    }

    /// The tabs beside the one in front and the menu, each with the gap before it.
    private static func beside(_ others: [Other], layout: Layout, gap: Double, more: Double) -> Double {
        let shown = others.prefix(layout.shown)
        return shown.map(layout.width(of:)).reduce(0, +) + gap * Double(shown.count) + (layout.hidden > 0 ? more + gap : 0)
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
    /// Under memory pressure only the tab in front is kept.
    ///
    /// - Parameters:
    ///   - alive: the tabs whose screens are alive now.
    ///   - left: when each tab last went behind another. A tab alive without one is treated as just left.
    public static func alive<ID: Hashable>(selected: ID, alive: Set<ID>, left: [ID: Date], now: Date, policy: Policy,
                                          pressure: Bool = false) -> Set<ID> {
        guard !pressure else { return [selected] }
        let behind = alive.subtracting([selected])
            .map { (id: $0, left: left[$0] ?? now) }
            .filter { now.timeIntervalSince($0.left) < policy.idle }
            .sorted { $0.left > $1.left }
            .prefix(max(0, policy.limit))
        return Set(behind.map(\.id)).union([selected])
    }
}
