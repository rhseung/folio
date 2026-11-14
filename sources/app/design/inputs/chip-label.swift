import FolioDomain
import SwiftUI

struct ChipLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            Text(text).lineLimit(1).frame(maxWidth: 240, alignment: .leading).fixedSize()
            Image(systemName: "chevron.up.chevron.down")
                .font(Theme.Glyph.small)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .chip()
    }
}
