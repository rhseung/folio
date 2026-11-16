import FolioDomain
import SwiftUI

struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
        .chip()
    }
}
