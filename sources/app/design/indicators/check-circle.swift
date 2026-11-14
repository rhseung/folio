import FolioDomain
import SwiftUI

struct CheckCircle: View {
    @Environment(\.accent) private var accent
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(Theme.Glyph.check)
                .foregroundStyle(on ? accent.color : Theme.Palette.textTertiary)
        }
        .buttonStyle(.pointing(.plain))
    }
}
