import FolioDomain
import SwiftUI

struct PageBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.columnButtons) private var columnButtons

    var body: some View {
        let afterButtons = Theme.Space.s + CGFloat(columnButtons) * (Theme.Size.toolbarButton + Theme.Space.s)
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.xxs) {
                leading
                Spacer(minLength: Theme.Space.s)
                trailing
            }
            .lineLimit(1)
            .buttonStyle(.toolbar)
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .padding(.leading, columnButtons > 0 ? afterButtons : Theme.Space.m)
            .padding(.trailing, Theme.Space.m)
            .padding(.vertical, columnButtons > 0 ? Theme.Space.s : Theme.Space.xs)
            Theme.Palette.lineSoft.frame(height: 1)
        }
    }
}
