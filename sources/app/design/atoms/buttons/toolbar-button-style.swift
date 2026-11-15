import SwiftUI

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarButton(configuration: configuration)
    }
}

private struct ToolbarButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label.labelStyle(.iconOnly)
            .font(Theme.Glyph.toolbar)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.Palette.chromeIcon)
            .frame(minWidth: Theme.Size.toolbarButton, minHeight: Theme.Size.toolbarButton)
            .background {
                Capsule().fill(Theme.Palette.text).opacity(
                    configuration.isPressed ? Theme.Opacity.pressed : hovering && isEnabled ? Theme.Opacity.hover : 0
                )
                .padding(Theme.Space.xxs)
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
            .onHover { hovering = $0 }
    }
}
