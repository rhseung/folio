import FolioDomain
import SwiftUI

struct FlowChips<Item: Hashable>: View {
    @Environment(\.accent) private var accent
    let items: [Item]
    let selected: Set<Item>
    let label: (Item) -> String
    let toggle: (Item) -> Void

    var body: some View {
        WrapLayout(spacing: Theme.Space.tight) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    toggle(item)
                } label: {
                    Text(label(item))
                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                        .padding(Theme.Inset.toggle)
                        .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
    }
}
