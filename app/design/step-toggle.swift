import SwiftUI

/// A few states stepped through by pressing, like an effort switch: each press moves to the next and wraps around,
/// a right click jumps to any. Ordered states (progress) show rising bars filled up to the current one; unordered
/// ones (attendance) light only the current dot.
struct StepToggle<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
        let tint: Color
    }

    @Binding var selection: Value
    let options: [Option]
    var ordered = true

    var index: Int { options.firstIndex { $0.value == selection } ?? 0 }

    var body: some View {
        let current = options[index]
        Button {
            selection = options[(index + 1) % options.count].value
        } label: {
            HStack(spacing: Theme.Space.tight) {
                HStack(alignment: .bottom, spacing: Theme.Space.xxs) {
                    ForEach(options.indices, id: \.self) { i in
                        let lit = ordered ? i <= index : i == index
                        Capsule()
                            .fill(lit ? current.tint : Theme.Palette.textTertiary.opacity(0.35))
                            .frame(width: 4, height: ordered ? 4 + CGFloat(i) * 2 : 4)
                    }
                }
                .frame(height: 10, alignment: .bottom)
                Text(current.label)
                    .contentTransition(.interpolate)
                    .foregroundStyle(current.tint)
            }
            .font(Theme.Typeface.caption.weight(.semibold))
            .padding(.horizontal, Theme.Space.s + 2)
            .padding(.vertical, Theme.Space.xs)
            .background(current.tint.opacity(Theme.Opacity.tint), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.pointing(.plain))
        .animation(.snappy(duration: 0.2), value: selection)
        .sensoryFeedback(.levelChange, trigger: selection)
        .contextMenu {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].label) { selection = options[i].value }
            }
        }
        .help("눌러서 다음 상태로, 오른쪽 클릭으로 바로 고르기")
        .accessibilityLabel(current.label)
    }
}
