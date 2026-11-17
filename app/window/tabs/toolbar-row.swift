import FolioDomain
import SwiftUI

// `placement`만 관찰한다. 이 값을 계산하는 재료는 live resize의 frame마다 바뀌고, root view의 state로 두었을 때는
// 사이드바, 남겨 둔 모든 탭의 화면, 탭을 frame마다 다시 그렸다.
@MainActor @Observable final class ToolbarRow {
    struct Measures: Equatable {
        var front = TabFit.Tab.single
        var others: [TabFit.Tab] = []
        var more: CGFloat = 0
    }

    struct Placement: Equatable {
        var lead: CGFloat
        var fit: TabFit.Layout
        var width: CGFloat
        var newTabSpacing: CGFloat
    }

    static let bounds = TabFit.Bounds(min: Theme.Size.tabMin, max: Theme.Size.tabMax, grid: Theme.Space.xs)

    private(set) var placement = Placement(
        lead: 0, fit: TabFit.Layout(share: 0, shown: 0, hidden: 0), width: 0, newTabSpacing: TabBar.gap)

    // 창이 resize 되는 동안 줄이 배치되기 전에 설정되므로(`WindowWidth`) 탭이 같은 frame에 새 폭에 맞는다. 배치된 줄에서
    // 재면 창보다 한 frame 늦고, 줄보다 넓은 strip이 첫 탭을 패널 가장자리 밖으로 밀어냈다.
    @ObservationIgnored var windowWidth: CGFloat = 1200 { didSet { settle() } }
    @ObservationIgnored var leadingX = TitleRowEdges.lead(fullScreen: false) { didSet { settle() } }
    @ObservationIgnored var trailingWidth = ToolbarRow.trailingEstimate { didSet { settle() } }
    @ObservationIgnored var panelEdge: CGFloat = Theme.Size.sidebar { didSet { settle() } }
    @ObservationIgnored var measures = Measures() { didSet { settle() } }

    init() { settle() }

    var historyEnd: CGFloat { leadingX + Theme.Size.toolbarButton + RootView.historyGap + HistoryButtons.width }

    var lead: CGFloat { TabFit.lead(panelEdge: panelEdge, after: historyEnd, gap: Theme.Space.s) }

    var room: CGFloat {
        let end = windowWidth - trailingWidth - TitleRowEdges.trailing
        return end - historyEnd - lead - Theme.Space.s
    }

    private func settle() {
        let m = measures
        let plus = CGFloat(TabFit.newTabSpacing(gap: TabBar.gap, button: Theme.Size.toolbarButton, glyph: TabBar.plusInk))
        let space = room - Theme.Size.toolbarButton - plus
        let fit = TabFit.layout(room: space, front: m.front, others: m.others, gap: TabBar.gap, more: m.more, bounds: Self.bounds)
        let width =
            TabFit.width(front: m.front, others: m.others, layout: fit, gap: TabBar.gap, more: m.more) + plus + Theme.Size.toolbarButton
        // point 단위로 내린다. 올리면 strip이 줄보다 1point 커질 수 있다.
        let whole = (lead + width).rounded(.down) - lead
        let new = Placement(lead: lead, fit: fit, width: whole, newTabSpacing: plus)
        if new != placement { placement = new }
    }

    static let trailingEstimate = Theme.Size.searchField + Theme.Space.s + Theme.Size.toolbarButton * 5 + Theme.Space.xxs * 4
}
