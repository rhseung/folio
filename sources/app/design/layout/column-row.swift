import FolioDomain
import SwiftUI

struct ColumnRow<Trailing: View>: View {
    let title: String
    let symbol: String
    let chosen: Bool
    var tint: Color = Theme.Palette.text
    var fill: Color = Theme.Palette.fill
    @ViewBuilder var trailing: Trailing

    static var titleInset: CGFloat { Theme.Inset.listRow.leading + Theme.Size.tile + gap }
    static var gap: CGFloat { Theme.Space.s + 2 }

    var body: some View {
        HStack(spacing: Self.gap) {
            LineIcon(symbol: symbol, filled: chosen).foregroundStyle(chosen ? tint : Theme.Palette.textSecondary)
            Text(title).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            trailing.lineLimit(1).fixedSize()
        }
        .padding(.horizontal, Theme.Inset.listRow.leading)
        .padding(.vertical, Theme.Space.xs)
        .foregroundStyle(Theme.Palette.text)
        .fontWeight(chosen ? .semibold : .regular)
        .background(chosen ? fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
        .contentShape(.rect)
    }
}

extension ColumnRow where Trailing == EmptyView {
    init(title: String, symbol: String, chosen: Bool) {
        self.init(title: title, symbol: symbol, chosen: chosen) { EmptyView() }
    }
}
