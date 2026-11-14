import FolioDomain
import FolioMarkdown
import SwiftUI

struct MathPaletteCell: View {
    let item: CompletionItem
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    static let minWidth: CGFloat = 80
    static let height: CGFloat = 64
    static let glyphHeight: CGFloat = 32
    static let glyphSlot = CGSize(width: minWidth - 2 * Theme.Space.s, height: glyphHeight + 2 * NoteMath.edge(NoteLook.body))

    var body: some View {
        Button(action: pick) {
            VStack(spacing: Theme.Space.xs) {
                glyph.frame(height: Self.glyphHeight)
                Text(item.title)
                    .font(Theme.Typeface.caption).monospaced()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(Theme.Space.xs)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background(hovering ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .onHover { hovering = $0 }
        .help(item.detail ?? item.title)
        .accessibilityLabel(item.title)
    }

    @ViewBuilder var glyph: some View {
        if let formula = item.preview,
            let picture = NoteMath.shared.picture(
                formula, syntax: item.previewAsciiMath ? .asciimath : .latex, display: false, size: NoteLook.body,
                dark: scheme == .dark)
        {
            let fitted = picture.fitted(Self.glyphSlot)
            Image(platformImage: picture.image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
        } else {
            Image(systemName: "square.dashed").font(Theme.Glyph.regular).foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}
