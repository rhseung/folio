import FolioDomain
import SwiftUI

struct SegmentedControl<Value: Hashable>: View {
    // `track`은 회색 트랙 안의 판으로 2~4개를 한 줄에 둔다. `flow`는 칩마다 따로 서서 줄을 바꾸므로 다섯 개가 넘어도 잘리지 않는다.
    enum Arrangement { case track, flow }

    @Binding var selection: Value
    let options: [(Value, String)]
    var layout = Arrangement.track
    var systemImages: [String] = []
    var size = ControlSize.regular
    var tints: [Color?] = []
    @Environment(\.onGlass) private var onGlass
    @Environment(\.accent) private var accent

    var body: some View {
        switch layout {
        case .track: track
        case .flow: flow
        }
    }

    var track: some View {
        let compact = size == .small || size == .mini || onGlass
        return HStack(spacing: Theme.Space.xxs) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let chosen = selection == value
                option(i) {
                    Group {
                        if systemImages.indices.contains(i) {
                            LineIcon(symbol: systemImages[i], filled: chosen)
                        } else {
                            Text(label).lineLimit(1)
                        }
                    }
                    .fontWeight(chosen ? .semibold : .regular)
                    .foregroundStyle(tints.indices.contains(i) ? tints[i] ?? labelColor(chosen) : labelColor(chosen))
                    .padding(Theme.Inset.toggle)
                    .background(
                        chosen
                            ? (compact ? AnyShapeStyle(Theme.Palette.text.opacity(Theme.Opacity.tint)) : AnyShapeStyle(Theme.Palette.card))
                            : AnyShapeStyle(.clear), in: .capsule
                    )
                    .contentShape(.capsule)
                }
                .help(systemImages.isEmpty ? "" : label)
                .accessibilityLabel(label)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(compact ? Theme.Space.xxs : Theme.Space.xs)
        .fixedSize()
        .background(
            compact ? AnyShapeStyle(Theme.Palette.text.opacity(Theme.Opacity.wash)) : AnyShapeStyle(Theme.Palette.fill), in: .capsule)
    }

    var flow: some View {
        FlowLayout(spacing: Theme.Space.tight) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let chosen = selection == value
                option(i) {
                    Text(label)
                        .lineLimit(1)
                        .font(Theme.Typeface.caption.weight(chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? accent.ink : Theme.Palette.textSecondary)
                        .chip(fill: chosen ? accent.tint : nil)
                        .contentShape(TouchTarget())
                }
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    func option(_ i: Int, @ViewBuilder label: () -> some View) -> some View {
        let value = options[i].0
        return Button {
            selection = value
        } label: {
            label()
        }
        .buttonStyle(.pointing(.plain))
    }

    func labelColor(_ chosen: Bool) -> Color { chosen ? Theme.Palette.text : Theme.Palette.textSecondary }
}
