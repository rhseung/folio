import FolioDomain
import SwiftUI

struct ToggleChips<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
        var symbol: String?
    }

    // `circle`은 한 글자 선택지(요일)를 같은 크기의 원으로 둔다.
    enum ChipShape { case capsule, circle }

    @Binding var selection: Set<Value>
    let options: [Option]
    var shape = ChipShape.capsule
    var allowsEmptySelection = true
    @Environment(\.accent) private var accent

    var body: some View {
        FlowLayout(spacing: shape == .circle ? Theme.Space.xs : Theme.Space.tight, centered: shape == .capsule) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = selection.contains(option.value)
                Button {
                    toggle(option.value)
                } label: {
                    label(option, on: on)
                        .fontWeight(on ? .semibold : .regular)
                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                        .contentShape(TouchTarget())
                        .fixedSize()
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder func label(_ option: Option, on: Bool) -> some View {
        switch shape {
        case .capsule:
            HStack(spacing: Theme.Space.xs) {
                if let symbol = option.symbol { Image(systemName: symbol).imageScale(.small) }
                Text(option.label).lineLimit(1)
            }
            .chip(fill: on ? accent.tint : nil)
        case .circle:
            Text(option.label)
                .font(Theme.Typeface.caption)
                .frame(width: 28, height: 28)  // design: one-off, a one-letter day in a round toggle
                .background(on ? accent.tint : Theme.Palette.fill, in: .circle)
        }
    }

    func toggle(_ value: Value) {
        if !selection.contains(value) {
            selection.insert(value)
        } else if allowsEmptySelection || selection.count > 1 {
            selection.remove(value)
        }
    }
}
