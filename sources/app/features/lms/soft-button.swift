import FolioDomain
import SwiftUI

struct SoftButton: View {
    let configuration: ButtonStyleConfiguration
    let strong: Bool
    let iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let strength = Theme.Opacity.tint * (configuration.isPressed ? 2 : hovering && isEnabled ? 1.5 : 1)
        Group {
            if iconOnly {
                configuration.label.labelStyle(.iconOnly)
                    .frame(width: Theme.Space.xl + Theme.Space.xs, height: Theme.Space.xl + Theme.Space.xs)
            } else {
                configuration.label
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.xs + Theme.Space.xxs)
            }
        }
        .font(strong ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
        .lineLimit(1)
        .foregroundStyle(strong ? Theme.Palette.text : Theme.Palette.textSecondary)
        .background(Theme.Palette.textSecondary.opacity(strength), in: .capsule)
        .contentShape(TouchTarget())
        .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
        .onHover { hovering = $0 }
        #if os(macOS)
        .pointerStyle(isEnabled ? .link : nil)
        #endif
    }
}
