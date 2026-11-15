import FolioDomain
import SwiftUI

struct EmptyCard: View {
    let symbol: String
    var tone: Tone = .plain
    let title: String
    var detail: String?

    var body: some View {
        Card {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: symbol)
                    .font(Theme.Glyph.check)
                    .foregroundStyle(tone == .plain ? Theme.Palette.textTertiary : tone.foreground)
                    .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton)
                    .background(
                        tone == .plain ? Theme.Palette.fill : tone.foreground.opacity(Theme.Opacity.tint),
                        in: .rect(cornerRadius: Theme.Radius.control))
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                    if let detail { Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Inset.row)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
        }
    }
}
