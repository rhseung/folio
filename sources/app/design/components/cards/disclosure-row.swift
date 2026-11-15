import FolioDomain
import SwiftUI

struct DisclosureRow<Rows: View>: View {
    let label: String
    @Binding var isOpen: Bool
    var last = false
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { isOpen.toggle() }
            } label: {
                CardRow(last: last && !isOpen) {
                    Text(label).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Image(systemName: "chevron.right")
                        .font(Theme.Glyph.small)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .accessibilityValue(Text(isOpen ? .designExpanded : .designCollapsed))
            if isOpen {
                VStack(alignment: .leading, spacing: 0) { rows }
                    .padding(.leading, Theme.Space.l)
                    .background(Theme.Palette.fill.opacity(Theme.Opacity.folded))
            }
        }
    }
}
