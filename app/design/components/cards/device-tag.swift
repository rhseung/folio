import FolioDomain
import SwiftUI

struct DeviceTag: View {
    var body: some View {
        Text(.designThisDevice)
            .font(Theme.Typeface.label)
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.tight)
            .padding(.vertical, Theme.Space.xxs)
            .overlay(Capsule().strokeBorder(Theme.Palette.line))
            .fixedSize()
    }
}
