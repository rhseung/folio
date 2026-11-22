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
                Image(systemName: "flag.fill").font(Theme.Glyph.small)
                Text(model.deadline(entry, other: other)).font(Theme.Typeface.caption.weight(.semibold))
                    .strikethrough(closed).lineLimit(2).multilineTextAlignment(.leading)
            }
            .foregroundStyle(closed ? Theme.Palette.textTertiary : Theme.Palette.danger)
            .padding(.horizontal, Theme.Space.xxs)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.touchTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .accessibilityLabel(model.spoken(entry))
    }
}
