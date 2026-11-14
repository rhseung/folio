import FolioDomain
import SwiftUI

struct ChipTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.accent) private var accent

    var body: some View {
        FlowLayout(spacing: Theme.Space.tight) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .lineLimit(1)
                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                        .padding(Theme.Inset.toggle)
                        .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                        .contentShape(TouchTarget())
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
