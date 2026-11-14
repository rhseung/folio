import FolioDomain
import SwiftUI

struct ToggleChips<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
        let symbol: String
    }

    @Binding var selection: Set<Value>
    let options: [Option]

    var body: some View {
        FlowLayout(spacing: Theme.Space.tight, centered: true) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = selection.contains(option.value)
                Button {
                    if on { selection.remove(option.value) } else { selection.insert(option.value) }
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: option.symbol).imageScale(.small)
                        Text(option.label).lineLimit(1)
                    }
                    .fontWeight(on ? .semibold : .regular)
                    // 채운 배경에서는 `onFill`이 아니라 `card` 색을 쓴다. 다크 모드의 밝은 파랑 위에서 흰 글자는 대비가
                    // 3:1보다 낮다.
                    .foregroundStyle(on ? Theme.Palette.card : Theme.Palette.textSecondary)
                    .padding(Theme.Inset.toggle)
                    .background(on ? Theme.Palette.info : Theme.Palette.fill, in: .capsule)
                    .contentShape(.capsule)
                    .fixedSize()
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
