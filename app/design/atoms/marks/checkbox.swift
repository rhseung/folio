import FolioDomain
import SwiftUI

struct Checkbox: View {
    @Environment(\.accent) private var accent
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(Theme.Glyph.check)
                .foregroundStyle(isOn ? accent.color : Theme.Palette.textTertiary)
        }
        .buttonStyle(.pointing(.plain))
    }
}
