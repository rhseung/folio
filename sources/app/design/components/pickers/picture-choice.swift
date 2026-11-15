import FolioDomain
import SwiftUI

struct PictureChoice<Value: Hashable, Picture: View>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @ViewBuilder var picture: (Value) -> Picture

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let chosen = selection == value
                Button {
                    selection = value
                } label: {
                    VStack(spacing: Theme.Space.xs) {
                        picture(value).frame(width: Self.picture.width, height: Self.picture.height)
                        Text(label).font(Theme.Typeface.caption).lineLimit(1)
                    }
                    .fontWeight(chosen ? .semibold : .regular)
                    .foregroundStyle(chosen ? Theme.Palette.info : Theme.Palette.textSecondary)
                    .padding(.vertical, Theme.Space.tight)
                    .padding(.horizontal, Theme.Space.s)
                    .background(
                        chosen ? Theme.Palette.info.opacity(Theme.Opacity.tint) : .clear, in: .rect(cornerRadius: Theme.Radius.control)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(
                            chosen ? Theme.Palette.info : Theme.Palette.lineSoft)
                    )
                    .contentShape(.rect(cornerRadius: Theme.Radius.control))
                    .fixedSize()
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityLabel(label)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    static var picture: CGSize { CGSize(width: 44, height: 28) }
}
