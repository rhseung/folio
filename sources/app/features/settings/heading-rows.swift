import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

struct HeadingRows: View {
    @Binding var lines: [String]
    var last = false

    var body: some View {
        ForEach(lines.indices, id: \.self) { i in
            CardRow {
                Text("\(i + 1)").monospacedDigit().foregroundStyle(Theme.Palette.textTertiary).frame(width: 18, alignment: .trailing)
                // 목록을 다시 그리는 동안 지운 행에 글을 한 번 더 물을 수 있으므로 인덱스를 확인한다.
                TextField(
                    String(localized: .settingsHeading),
                    text: Binding(
                        get: { lines.indices.contains(i) ? lines[i] : "" }, set: { if lines.indices.contains(i) { lines[i] = $0 } })
                )
                .textFieldStyle(.plain)
                Button {
                    lines.remove(at: i)
                } label: {
                    Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.pointing(.plain))
                .help(Text(.commonDelete))
            }
            .contextMenu { Button(.commonDelete, role: .destructive) { if lines.indices.contains(i) { lines.remove(at: i) } } }
        }
        CardRow(last: last) {
            Button {
                lines.append("")
            } label: {
                Label(.settingsAddHeading, systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.pointing(.plain))
        }
    }
}
