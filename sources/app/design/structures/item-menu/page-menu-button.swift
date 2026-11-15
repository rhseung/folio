import FolioDomain
import SwiftUI

struct PageMenuButton<Items: View>: View {
    var inBar = false
    @ViewBuilder var items: Items

    var body: some View {
        if inBar {
            Menu {
                items
            } label: {
                Label(.menuMore, systemImage: "ellipsis")
            }
            .help(Text(.menuMore))
        } else {
            Menu {
                items
            } label: {
                Label(.menuMore, systemImage: "ellipsis").labelStyle(.iconOnly)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton)
                    .contentShape(TouchTarget())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(.menuMore))
        }
    }
}
