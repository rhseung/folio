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
                // 여러 줄의 가운데 줄임은 마지막 줄 끝에 이름의 끝을 남기지만, 아주 좁으면 확장자의 점부터 잘린다.
                // 그 폭에서는 확장자를 따로 두는 한 줄로 바꾼다. 잰 폭을 상태에 두고 고르면 시트처럼 크기를 내용에
                // 맞추는 곳에서 배치가 되먹임되어 한 줄 쪽에 멈추므로, 상태 없이 제안된 폭으로 고른다.
                ViewThatFits(in: .horizontal) {
                    // 시트의 행은 한 줄 높이를 제안받아, 높이를 고정하지 않으면 줄을 넘기지 않고 가운데를 줄인다.
                    Text(name).lineLimit(lineLimit).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
                        .frame(idealWidth: Theme.Size.fileNameRoom, alignment: .leading)
                    split
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
