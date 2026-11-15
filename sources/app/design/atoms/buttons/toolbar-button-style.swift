import SwiftUI

// `.controlSize(.small)`은 다른 캡슐 안(녹음 막대)에 드는 작은 원이다. 바깥 캡슐의 높이는 그대로 두고 원만 줄인다.
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarButton(configuration: configuration)
    }
}

private struct ToolbarButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    var body: some View {
        if controlSize == .small || controlSize == .mini { small } else { regular }
    }

    var regular: some View {
        configuration.label.labelStyle(.iconOnly)
            .font(Theme.Glyph.toolbar)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.Palette.chromeIcon)
            .frame(minWidth: Theme.Size.toolbarButton, minHeight: Theme.Size.toolbarButton)
            .background {
                Capsule().fill(Theme.Palette.text).opacity(highlight).padding(Theme.Space.xxs)
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
            .onHover { hovering = $0 }
    }

    var small: some View {
        configuration.label.labelStyle(.iconOnly)
            .font(Theme.Typeface.bodyStrong)
            .foregroundStyle(Theme.Palette.chromeIcon)
            .frame(width: Self.smallSide, height: Self.smallSide)
            .background { Circle().fill(Theme.Palette.text).opacity(highlight) }
            .frame(height: Theme.Size.toolbarButton)
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
            .onHover { hovering = $0 }
    }

    var highlight: Double { configuration.isPressed ? Theme.Opacity.pressed : hovering && isEnabled ? Theme.Opacity.hover : 0 }

    static let smallSide = Theme.Size.toolbarButton - Theme.Space.s
}
