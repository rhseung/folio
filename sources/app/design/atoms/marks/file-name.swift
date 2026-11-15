import FolioDomain
import SwiftUI

struct FileName: View {
    let name: String
    var lineLimit = 2
    var isFolder = false
    var help: String?
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    init(_ name: String, lineLimit: Int = 2, isFolder: Bool = false, help: String? = nil) {
        self.name = name
        self.lineLimit = lineLimit
        self.isFolder = isFolder
        self.help = help
    }

    var body: some View {
        Group {
            if lineLimit == 1 {
                split
            } else {
                FileNameFit {
                    Text(name).lineLimit(lineLimit).truncationMode(.middle).folding
                    split.folding
                }
            }
        }
        .background {
            Text(name).fixedSize(horizontal: false, vertical: true).hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { shownHeight = $0 }
        .help(help ?? (isCut ? name : ""))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    var isCut: Bool { fullHeight > shownHeight + 1 }

    var split: some View {
        let parts = FileNameParts(name, isFolder: isFolder)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.stem).lineLimit(1).truncationMode(.middle)
            if !parts.suffix.isEmpty { Text(parts.suffix).lineLimit(1).layoutPriority(1) }
        }
    }
}

// 여러 줄의 가운데 줄임은 마지막 줄 끝에 이름의 끝을 남기지만, 아주 좁으면 확장자의 점부터 잘린다. 그 폭에서는 확장자를 떼어
// 둔 한 줄(둘째 꼴)을 쓴다. `ViewThatFits`가 아니라 layout으로 고른다. 페이지 scroll view 안에서 `ViewThatFits`는 고르지 않은
// 후보만큼 스크롤 높이를 늘렸다. 잰 폭을 상태에 두고 고르면 시트처럼 크기를 내용에 맞추는 곳에서 배치가 되먹임되어 한 꼴에 멈췄다.
// 높이는 제안을 따르지 않고 꼴이 스스로 정한다. 시트의 행은 한 줄 높이를 제안해 두 줄로 넘기지 못하게 했다.
private struct FileNameFit: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (chosen, width) = pick(proposal.width, subviews)
        return chosen.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (chosen, _) = pick(bounds.width, subviews)
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: subview == chosen ? ProposedViewSize(bounds.size) : .zero)
        }
    }

    private func pick(_ offered: CGFloat?, _ subviews: Subviews) -> (LayoutSubview, CGFloat?) {
        let width = offered.flatMap { $0.isFinite ? $0 : nil }
        // 한 줄에 다 들어가는 짧은 이름은 좁아도 그대로 둔다. 떼어 둔 꼴은 글자 사이가 달라 같은 폭에서 잘렸다.
        if let width, width < Theme.Size.fileNameRoom, subviews[0].sizeThatFits(.unspecified).width > width {
            return (subviews[1], width)
        }
        return (subviews[0], width)
    }
}

extension View {
    // 높이가 제안을 그대로 따르게 해서, `FileNameFit`이 높이 0을 제안한 꼴은 잘려 보이지 않는다.
    fileprivate var folding: some View { frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped() }
}
