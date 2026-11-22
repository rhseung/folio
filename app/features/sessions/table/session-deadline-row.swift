import FolioDomain
import SwiftUI

// 과제 마감 한 줄이다. 블록이 아니라 깃발과 글만 두어 수업 블록과 구분하고, 누르면 그 과제로 간다.
struct SessionDeadlineRow: View {
    @Environment(\.openLink) private var openLink
    let model: SessionsModel
    let entry: SessionTableEntry
    var other = false

    var body: some View {
        let closed = entry.look == .deadlineClosed
        Button {
            if let link = model.link(entry) { openLink(link, course: model.courseId) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Image(systemName: "flag.fill").font(Theme.Glyph.small).accessibilityHidden(true)
                Text(model.deadline(entry, other: other)).font(Theme.Typeface.caption.weight(.semibold))
                    .strikethrough(closed).lineLimit(2).multilineTextAlignment(.leading)
            }
            // 지난 마감도 회색으로 흐리지 않는다. 취소선만으로 끝난 것을 알리고, 마감은 끝까지 눈에 띄어야 한다.
            .foregroundStyle(Theme.Palette.danger)
            .padding(.horizontal, Theme.Space.xxs)
            .padding(.vertical, Theme.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 줄은 글 높이만 차지하고, 누르는 자리만 위아래로 넓혀 44pt를 넘긴다.
            .contentShape(.rect.inset(by: -Theme.Space.m))
        }
        .buttonStyle(.pointing(.plain))
        .accessibilityLabel(model.spoken(entry))
    }
}
