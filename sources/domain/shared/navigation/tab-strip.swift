import Foundation

public struct TabStrip<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var tabs: [ID]
    public private(set) var selected: ID

    public init(_ first: ID) {
        tabs = [first]
        selected = first
    }

    public init?(tabs: [ID], selected: ID) {
        guard tabs.contains(selected), Set(tabs).count == tabs.count else { return nil }
        self.tabs = tabs
        self.selected = selected
    }

    public var selectedIndex: Int { tabs.firstIndex(of: selected) ?? 0 }

    public mutating func open(_ id: ID, afterSelected: Bool = false) {
        guard !tabs.contains(id) else { return select(id) }
        tabs.insert(id, at: afterSelected ? selectedIndex + 1 : tabs.count)
        selected = id
    }

    public mutating func select(_ id: ID) {
        if tabs.contains(id) { selected = id }
    }

    public mutating func select(number n: Int) {
        if n == 9, let last = tabs.last { return selected = last }
        if tabs.indices.contains(n - 1) { selected = tabs[n - 1] }
    }

    public mutating func selectNext() { selected = tabs[(selectedIndex + 1) % tabs.count] }
    public mutating func selectPrevious() { selected = tabs[(selectedIndex + tabs.count - 1) % tabs.count] }

    @discardableResult
    public mutating func close(_ id: ID) -> Bool {
        guard tabs.count > 1, let i = tabs.firstIndex(of: id) else { return false }
        tabs.remove(at: i)
        if selected == id { selected = tabs[min(i, tabs.count - 1)] }
        return true
    }

    public mutating func closeOthers(than id: ID) {
        guard tabs.contains(id) else { return }
        tabs = [id]
        selected = id
    }

    public mutating func move(_ id: ID, to index: Int) {
        guard let i = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: i)
        tabs.insert(id, at: max(0, min(index, tabs.count)))
    }
}

public enum TabFit {
    public struct Other: Equatable, Sendable {
        public var full: Double
        public var icons: Double
        public var stacked: Double

        public init(full: Double, icons: Double, stacked: Double) {
            self.full = full
            self.icons = icons
            self.stacked = stacked
        }

        public init(single full: Double, icon: Double) {
            self.init(full: full, icons: icon, stacked: icon)
        }
    }

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
        public var iconsOnly: Bool
        public var stacked: Bool
        public var compactFront: Bool
        public var shown: Int
        public var hidden: Int

        public init(iconsOnly: Bool, stacked: Bool = false, compactFront: Bool = false, shown: Int, hidden: Int) {
            self.iconsOnly = iconsOnly
            self.stacked = stacked
            self.compactFront = compactFront
            self.shown = shown
            self.hidden = hidden
        }

        public var step: Int {
            hidden > 0 ? 4 : compactFront ? 3 : stacked ? 2 : iconsOnly ? 1 : 0
        }

        public func width(of tab: Other) -> Double {
            !iconsOnly ? tab.full : stacked ? tab.stacked : tab.icons
        }
    }

    // 캡슐은 자기 내용에 여백을 두므로, 맨 위치 표시가 쓰던 `Space.l` 여백을 더하면 첫 캡슐이 본문 패널의 앞
    // 가장자리(`panelEdge`)에 닿지 않는다. 가장자리가 버튼 아래나 그 근처에 있으면(사이드바를 접었을 때) 탭은
    // 버튼 뒤에 `gap`만 둔다.
    public static func lead(panelEdge: Double, after: Double, gap: Double) -> Double {
        max(gap, panelEdge - after)
    }

    public static func layout(room: Double, front: Front, others: [Other], gap: Double, more: Double) -> Layout {
        let n = others.count
        let steps = [
            Layout(iconsOnly: false, shown: n, hidden: 0),
            Layout(iconsOnly: true, shown: n, hidden: 0),
            Layout(iconsOnly: true, stacked: true, shown: n, hidden: 0),
            Layout(iconsOnly: true, stacked: true, compactFront: true, shown: n, hidden: 0),
        ]
        for step in steps where front.width(compact: step.compactFront) + beside(others, layout: step, gap: gap, more: more) <= room {
            return step
        }

        guard n > 0 else { return steps[3] }
        var fit = Layout(iconsOnly: true, stacked: true, compactFront: true, shown: n - 1, hidden: 1)
        while fit.shown > 0, front.width(compact: true) + beside(others, layout: fit, gap: gap, more: more) > room {
            fit.shown -= 1
            fit.hidden += 1
        }
        return fit
    }

    // 남는 폭이 있는 동안에는 nil이므로, 그 폭에서 창 크기를 바꿔도 탭은 바뀌지 않는다. 경로를 줄일 때는 줄이 남긴
    // 폭이 아무리 작아도 그 폭을 쓴다. 줄보다 넓은 탭 줄은 툴바의 다른 항목(검색 칸과 버튼)을 넘침 메뉴로 밀어낸다.
    public static func trail(room: Double, front: Front, others: [Other], layout: Layout, gap: Double, more: Double) -> Double? {
        let rest = room - beside(others, layout: layout, gap: gap, more: more) - front.chrome(compact: layout.compactFront)
        return front.trail <= rest ? nil : max(0, rest)
    }

    public static func width(front: Front, others: [Other], layout: Layout, trail: Double?, gap: Double, more: Double) -> Double {
        (trail ?? front.trail) + front.chrome(compact: layout.compactFront) + beside(others, layout: layout, gap: gap, more: more)
    }

    // 기본 간격만 두면 글리프 둘레의 버튼 여백 때문에 간격이 더 넓어 보인다. 그래서 `button` 폭 버튼의 가운데에
    // 놓인 글리프가 캡슐 사이 간격처럼 마지막 캡슐에서 `gap`만큼 떨어지게 한다. 여백이 `gap`보다 넓으면 값이
    // 음수가 되고, 이때 버튼의 히트 영역이 캡슐 가장자리 아래까지 닿는다.
    public static func newTabSpacing(gap: Double, button: Double, glyph: Double) -> Double {
        gap - (button - glyph) / 2
    }

    private static func beside(_ others: [Other], layout: Layout, gap: Double, more: Double) -> Double {
        let shown = others.prefix(layout.shown)
        return shown.map(layout.width(of:)).reduce(0, +) + gap * Double(shown.count) + (layout.hidden > 0 ? more + gap : 0)
    }
}

public enum TabKeep {
    public struct Policy: Equatable, Sendable {
        public var limit: Int
        public var idle: TimeInterval

        public init(limit: Int, idle: TimeInterval) {
            self.limit = limit
            self.idle = idle
        }
    }

    // 녹음을 재생하는 탭을 버리면 듣던 것이 멈추므로, 재생 중인 탭은 시간이나 메모리 압박과 상관없이 남기고 다른
    // 탭이 나눠 쓰는 `limit`에도 세지 않는다.
    public static func alive<ID: Hashable>(
        selected: ID, alive: Set<ID>, left: [ID: Date], now: Date, policy: Policy,
        pressure: Bool = false, playing: Set<ID> = []
    ) -> Set<ID> {
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
