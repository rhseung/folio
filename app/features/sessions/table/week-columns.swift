import SwiftUI

// 주차 여백 하나와 칸 여러 개를 한 줄로 놓는다. 수업 요일 칸은 같은 폭이고 마지막 "그 밖" 칸만 좁다. 줄의 높이는 가장
// 높은 칸을 따르고, 모든 칸에 그 높이를 주어 칸의 바탕과 구분선이 줄 끝까지 닿게 한다.
struct WeekColumns: Layout {
    let gutter: CGFloat
    // "그 밖" 칸은 보강, 시험, 마감 몇 개만 담으므로 수업 칸의 0.8만 받는다.
    static let otherWeight = 0.8

    func widths(_ width: CGFloat, count: Int) -> [CGFloat] {
        let cells = max(count - 1, 0)
        guard cells > 0 else { return [gutter] }
        let room = max(width - gutter, 0)
        let unit = room / (CGFloat(cells - 1) + Self.otherWeight)
        return [gutter] + Array(repeating: unit, count: cells - 1) + [unit * Self.otherWeight]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let widths = widths(width, count: subviews.count)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, width) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}
