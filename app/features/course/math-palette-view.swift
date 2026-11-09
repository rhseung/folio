import FolioDomain
import FolioMarkdown
import SwiftUI

/// The popover of the note bar's f(x): the note's math syntax on top, as the button's menu had it, then, while the
/// note is being written, every symbol of that syntax to put at the caret by touch or click (#392).
struct MathPalette: View {
    @Bindable var model: MathPaletteModel
    /// The read view has no caret, so it keeps only the syntax.
    let writing: Bool
    @Environment(\.accent) private var accent

    static let width: CGFloat = 400
    static let gridHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Text(.notesMathSyntax).foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: Theme.Space.s)
                Segmented(selection: $model.syntax, options: MathSyntax.allCases.map { ($0, $0.label) }, compact: true)
            }
            .padding(Theme.Space.m)
            if writing {
                Theme.Palette.line.frame(height: 1)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SearchField(prompt: String(localized: .notesMathSearch), text: $model.search)
                    // A search looks through every category, so the tabs step aside while there is one.
                    if !model.searching { tabs }
                }
                .padding([.horizontal, .top], Theme.Space.m)
                grid
            }
        }
        .frame(width: Self.width)
        .font(Theme.Typeface.body)
    }

    /// Eight categories are more than `Segmented` holds (2–4), so they wrap as a row of chips, each fully named.
    var tabs: some View {
        FlowLayout(spacing: Theme.Space.tight) {
            let shown = model.shown
            ForEach(model.categories, id: \.self) { category in
                let on = category == shown
                Button { model.category = category } label: {
                    Text(category.label)
                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                        .padding(Theme.Inset.toggle)
                        .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                        .contentShape(TouchTarget())
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    var grid: some View {
        let sections = model.sections
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(sections, id: \.category) { section in
                    if model.searching { Caption(section.category.label).padding(.horizontal, Theme.Space.xs) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: MathPaletteCell.minWidth), spacing: Theme.Space.xs)], spacing: Theme.Space.xs) {
                        ForEach(section.items) { item in
                            MathPaletteCell(item: item) { model.pick(item) }
                        }
                    }
                }
                if sections.isEmpty { EmptyLine(String(localized: .notesMathNoMatch)).padding(.horizontal, Theme.Space.xs) }
            }
            .padding(Theme.Space.m)
        }
        .overflowFade(.vertical)
        .frame(height: Self.gridHeight)
    }
}

/// A symbol as it looks, over the text that writes it.
struct MathPaletteCell: View {
    let item: CompletionItem
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    static let minWidth: CGFloat = 80
    static let height: CGFloat = 64
    static let glyphHeight: CGFloat = 28

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
        // A snippet's trigger is not what it writes; the tooltip says that.
        .help(item.detail ?? item.title)
        .accessibilityLabel(item.title)
    }

    @ViewBuilder var glyph: some View {
        if let formula = item.preview,
           let picture = NoteMath.picture(formula, syntax: item.previewAsciiMath ? .asciimath : .latex, display: false, size: NoteLook.body,
                                          color: NoteLook.text, dark: scheme == .dark) {
            Image(platformImage: picture.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: min(picture.size.width, Self.minWidth - 2 * Theme.Space.s), maxHeight: min(picture.size.height, Self.glyphHeight))
        } else {
            // Spacing and `\left` draw nothing of their own.
            Image(systemName: "square.dashed").font(Theme.Glyph.regular).foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}
