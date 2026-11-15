import FolioDomain
import SwiftUI

// `ViewThatFits`가 아니라 layout으로 만든다. 페이지 scroll view 안에서 `ViewThatFits`는 고르지 않은 후보만큼 페이지의
// 스크롤 높이를 늘렸다.
struct BlockHeading: Layout {
    var spacing: CGFloat = Theme.Space.s
    var lineSpacing: CGFloat = Theme.Space.xxs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let p = plan(proposal.width, subviews)
        return CGSize(width: p.width, height: p.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(bounds.width, subviews)
        let (title, note, action) = (subviews[0], subviews[1], subviews[2])
        let titleSize = title.sizeThatFits(ProposedViewSize(width: p.titleWidth, height: nil))
        let actionSize = action.sizeThatFits(.unspecified)
        let baseline = title.dimensions(in: ProposedViewSize(titleSize))[VerticalAlignment.firstTextBaseline]

        title.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: ProposedViewSize(width: p.titleWidth, height: nil))
        let actionBaseline = action.dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline]
        action.place(
            at: CGPoint(x: bounds.maxX - actionSize.width, y: bounds.minY + max(0, baseline - actionBaseline)), proposal: .unspecified)
        let noteProposal = ProposedViewSize(width: p.oneLine ? note.sizeThatFits(.unspecified).width : bounds.width, height: nil)
        if p.oneLine {
            let noteBaseline = note.dimensions(in: noteProposal)[VerticalAlignment.firstTextBaseline]
            note.place(
                at: CGPoint(x: bounds.minX + titleSize.width + spacing, y: bounds.minY + max(0, baseline - noteBaseline)),
                proposal: noteProposal)
        } else {
            note.place(at: CGPoint(x: bounds.minX, y: bounds.minY + p.lineHeight + lineSpacing), proposal: noteProposal)
        }
    }

    private func plan(_ offered: CGFloat?, _ subviews: Subviews) -> (
        width: CGFloat, height: CGFloat, titleWidth: CGFloat, oneLine: Bool, lineHeight: CGFloat
    ) {
        let (title, note, action) = (subviews[0], subviews[1], subviews[2])
        let t = title.sizeThatFits(.unspecified), n = note.sizeThatFits(.unspecified), a = action.sizeThatFits(.unspecified)
        let hasNote = n.width > 0, hasAction = a.width > 0
        let full = t.width + (hasNote ? spacing + n.width : 0) + (hasAction ? spacing + a.width : 0)
        let width = offered.flatMap { $0.isFinite ? $0 : nil } ?? full
        let oneLine = !hasNote || full <= width
        let room = width - (hasAction ? spacing + a.width : 0)
        let titleWidth = min(t.width, oneLine ? room - (hasNote ? spacing + n.width : 0) : room)
        let lineHeight = max(title.sizeThatFits(ProposedViewSize(width: max(titleWidth, 0), height: nil)).height, a.height)
        let height =
            oneLine
            ? max(lineHeight, n.height) : lineHeight + lineSpacing + note.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return (width, height, max(titleWidth, 0), oneLine, lineHeight)
    }
}
