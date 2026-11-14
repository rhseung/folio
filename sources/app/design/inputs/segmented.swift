import FolioDomain
import SwiftUI

struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var symbols: [String] = []
    var compact = false
    var inks: [Color?] = []
    @Environment(\.onGlass) private var onGlass

    var body: some View {
        let compact = compact || onGlass
        HStack(spacing: Theme.Space.xxs) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let chosen = selection == value
                Button {
                    selection = value
                } label: {
                    Group {
                        if symbols.indices.contains(i) { LineIcon(symbol: symbols[i], filled: chosen) } else { Text(label).lineLimit(1) }
                    }
                    .fontWeight(chosen ? .semibold : .regular)
                    .foregroundStyle(inks.indices.contains(i) ? inks[i] ?? labelColor(chosen) : labelColor(chosen))
                    .padding(Theme.Inset.toggle)
                    .background(
                        chosen
                            ? (compact ? AnyShapeStyle(Theme.Palette.text.opacity(Theme.Opacity.tint)) : AnyShapeStyle(Theme.Palette.card))
                            : AnyShapeStyle(.clear), in: .capsule
                    )
                    .contentShape(.capsule)
                }
                .buttonStyle(.pointing(.plain))
                .help(symbols.isEmpty ? "" : label)
                .accessibilityLabel(label)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(compact ? Theme.Space.xxs : Theme.Space.xs)
        .fixedSize()
        .background(
            compact ? AnyShapeStyle(Theme.Palette.text.opacity(Theme.Opacity.wash)) : AnyShapeStyle(Theme.Palette.fill), in: .capsule)
    }

    func labelColor(_ chosen: Bool) -> Color { chosen ? Theme.Palette.text : Theme.Palette.textSecondary }
}
