import FolioDomain
import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var centered = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(fit(bounds.width))
                let y = bounds.minY + row.y + (centered ? (row.height - size.height) / 2 : 0)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: fit(bounds.width))
                x += size.width + spacing
            }
        }
    }

    private func fit(_ width: CGFloat) -> ProposedViewSize {
        ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(fit(width))
            let added = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if added > width, !current.items.isEmpty {
                rows.append(current)
                current = ([i], current.y + current.height + spacing, size.width, size.height)
            } else {
                current = (current.items + [i], current.y, added, Swift.max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
