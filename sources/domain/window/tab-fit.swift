import Foundation

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
