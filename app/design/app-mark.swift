import SwiftUI

/// The app icon drawn in place: three bars, shorter going down. Drawn rather than read from the icon, which the iPad has
/// no API for and which an `.icon` file only becomes at build time.
struct AppMark: View {
    var side: CGFloat = Theme.Size.appMark

    var body: some View {
        // The icon's grid is 1024 wide: bars 168 high, 52 apart, starting 176 in, 664, 488 and 312 long.
        let unit = side / 1024
        VStack(alignment: .leading, spacing: 52 * unit) {  // design: one-off, the icon's own proportions
            bar(664 * unit, Theme.Palette.markInk)
            bar(488 * unit, Theme.Palette.markCoral)
            bar(312 * unit, Theme.Palette.markCoral)
        }
        .padding(.leading, 176 * unit)  // design: one-off, the icon's own proportions
        .frame(width: side, height: side, alignment: .leading)
        // The system's icon corner: a continuous rounded square about 22% of its side.
        .background(Theme.Palette.markBack, in: .rect(cornerRadius: side * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous).strokeBorder(Theme.Palette.lineSoft))
        .accessibilityHidden(true)
    }

    private func bar(_ length: CGFloat, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: length, height: 168 * side / 1024)
    }
}
