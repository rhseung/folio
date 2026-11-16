import FolioDomain
import SwiftUI

struct PatchNoteList: View {
    let items: [PatchNotes.Item]
    var maxHeight: CGFloat?
    var opening: () -> Void = {}
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        Card {
            if let maxHeight {
                ScrollView {
                    VStack(spacing: 0) { rows }
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            rowsHeight = $0
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .overflowFade(.vertical)
                // ScrollView는 받은 높이를 모두 차지하므로, 짧은 목록이 짧게 남도록 행 높이에 맞춘다.
                .frame(height: min(rowsHeight, maxHeight))
            } else {
                rows
            }
        }
    }

    var rows: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
            CardRow(last: i == items.count - 1) { PatchNoteRow(item: item, opening: opening) }
        }
    }
}
