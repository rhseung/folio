import Foundation

// 사파리처럼 탭 줄 폭을 이름이 있는 탭 수로 나눈다. 탭의 폭은 이름 길이를 따르지 않으므로, 탭을 열고 닫을 때만 바뀐다.
public enum TabFit {
    public enum Tab: Equatable, Sendable {
        // 나눈 폭을 받는 몫의 수다. 칸이 여럿인 고른 탭은 칸마다 한 몫을 받는다.
        case shares(Int)
        // 나누기에서 빠지는 탭(아이콘만 보이는 오늘, 칸 아이콘을 이은 탭)이 그려진 그대로의 폭이다.
        case fixed(Double)

        public static let single = Tab.shares(1)

        public var shareCount: Int {
            if case .shares(let n) = self { n } else { 0 }
        }

        public var fixedWidth: Double {
            if case .fixed(let width) = self { width } else { 0 }
        }
    }

    public struct Bounds: Equatable, Sendable {
        public var min: Double
        public var max: Double
        // 나눈 폭을 이 값의 배수로 내린다. 그래야 탭 하나를 열고 닫을 때 다른 탭이 1point씩 흔들리지 않는다.
        public var grid: Double

        public init(min: Double, max: Double, grid: Double) {
            self.min = min
            self.max = max
            self.grid = grid
        }
    }

    public struct Layout: Equatable, Sendable {
        public var share: Double
        public var shown: Int
        public var hidden: Int

        public init(share: Double, shown: Int, hidden: Int) {
            self.share = share
            self.shown = shown
            self.hidden = hidden
        }

        public func width(of tab: Tab) -> Double {
            switch tab {
            case .shares(let n): share * Double(n)
            case .fixed(let width): width
            }
        }
    }

    // 캡슐은 자기 내용에 여백을 두므로, 맨 위치 표시가 쓰던 `Space.l` 여백을 더하면 첫 캡슐이 본문 패널의 앞
    // 가장자리(`panelEdge`)에 닿지 않는다. 가장자리가 버튼 아래나 그 근처에 있으면(사이드바를 접었을 때) 탭은
    // 버튼 뒤에 `gap`만 둔다.
    public static func lead(panelEdge: Double, after: Double, gap: Double) -> Double {
        max(gap, panelEdge - after)
    }

    // 나눈 폭이 `bounds.min`보다 좁아지면 뒤쪽 탭부터 더 보기 메뉴로 보낸다. 고른 탭은 메뉴로 가지 않으므로, 그것만 남아도
    // 좁으면 고른 탭이 `bounds.min`보다 좁아진다. 그래야 탭 줄이 검색 칸 위로 넘어가지 않는다.
    public static func layout(room: Double, front: Tab, others: [Tab], gap: Double, more: Double, bounds: Bounds) -> Layout {
        for shown in stride(from: others.count, through: 0, by: -1) {
            let hidden = others.count - shown
            let tabs = [front] + others.prefix(shown)
            let shares = tabs.map(\.shareCount).reduce(0, +)
            let menu = hidden > 0 ? gap + more : 0
            let rest = room - tabs.map(\.fixedWidth).reduce(0, +) - gap * Double(shown) - menu
            guard shares > 0 else {
                if rest >= 0 || shown == 0 { return Layout(share: 0, shown: shown, hidden: hidden) }
                continue
            }
            let share = (rest / Double(shares) / bounds.grid).rounded(.down) * bounds.grid
            if share >= bounds.min || shown == 0 {
                return Layout(share: Swift.max(0, Swift.min(share, bounds.max)), shown: shown, hidden: hidden)
            }
        }
        return Layout(share: 0, shown: 0, hidden: others.count)
    }

    public static func width(front: Tab, others: [Tab], layout: Layout, gap: Double, more: Double) -> Double {
        let shown = others.prefix(layout.shown)
        return ([front] + shown).map(layout.width(of:)).reduce(0, +) + gap * Double(shown.count)
            + (layout.hidden > 0 ? gap + more : 0)
    }

    // 기본 간격만 두면 글리프 둘레의 버튼 여백 때문에 간격이 더 넓어 보인다. 그래서 `button` 폭 버튼의 가운데에
    // 놓인 글리프가 캡슐 사이 간격처럼 마지막 캡슐에서 `gap`만큼 떨어지게 한다. 여백이 `gap`보다 넓으면 값이
    // 음수가 되고, 이때 버튼의 히트 영역이 캡슐 가장자리 아래까지 닿는다.
    public static func newTabSpacing(gap: Double, button: Double, glyph: Double) -> Double {
        gap - (button - glyph) / 2
    }
}
