import FolioDomain
import SwiftUI

struct NoteCard: View {
    let text: NoteGalleryModel.CardText
    var compact = false

    var body: some View {
        let padding = compact ? Theme.Space.m : Theme.Space.l
        Card(padding: padding) {
            VStack(alignment: .leading, spacing: compact ? Theme.Space.tight : Theme.Space.s) {
                HStack(spacing: Theme.Space.tight) {
                    Image(systemName: "doc.text").accessibilityHidden(true)
                    Text(text.kind).lineLimit(1)
                    Spacer(minLength: 0)
                    if text.tex {
                        Text(verbatim: "TeX")  // strings: data, 형식 이름은 옮기지 않는다
                            .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textSecondary)
                            .padding(.horizontal, Theme.Space.xs)
                            .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.small))
                    }
                }
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

                Text(text.title)
                    .font(compact ? Theme.Typeface.bodyStrong : Theme.Typeface.bodyLarge.weight(.semibold))
                    .lineLimit(1)

                if !text.preview.isEmpty {
                    Text(text.preview)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(compact ? 2 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                HStack(spacing: Theme.Space.s) {
                    if !compact, let context = text.context {
                        Text(context).lineLimit(1).layoutPriority(1)
                        Spacer(minLength: 0)
                    }
                    Text(text.when).lineLimit(1).fixedSize()
                    if compact { Spacer(minLength: 0) }
                }
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(
                maxWidth: .infinity, minHeight: (compact ? Theme.Size.noteCardHeightCompact : Theme.Size.noteCardHeight) - padding * 2,
                alignment: .topLeading)
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.card))
    }
}
