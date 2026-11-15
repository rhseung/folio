import FolioDomain
import SwiftUI

struct SelectTrigger: View {
    let text: String
    var isFile = false
    init(_ text: String, isFile: Bool = false) {
        self.text = text
        self.isFile = isFile
    }

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            Group { if isFile { FileName(text, lineLimit: 1) } else { Text(text).lineLimit(1) } }
                .frame(maxWidth: 240, alignment: .leading).fixedSize()
            Image(systemName: "chevron.up.chevron.down")
                .font(Theme.Glyph.small)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .chip()
    }
}
