import FolioDomain
import FolioMarkdown
import SwiftUI

struct MathPalette: View {
    @Bindable var model: MathPaletteModel
    let writing: Bool

    static let width: CGFloat = 400
    static let gridHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Text(.notesMathSyntax).foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: Theme.Space.s)
                Segmented(selection: $model.syntax, options: MathSyntax.allCases.map { ($0, $0.label) }, compact: true)
                    .disabled(model.fence != nil)
            }
            .padding(Theme.Space.m)
            if writing {
                Theme.Palette.line.frame(height: 1)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SearchField(prompt: String(localized: .notesMathSearch), text: $model.search)
                    if !model.searching { tabs }
                }
                .padding([.horizontal, .top], Theme.Space.m)
                grid
            }
        }
        .frame(width: Self.width)
        .font(Theme.Typeface.body)
    }

    // 분류가 여덟 개라서 `Segmented`(2-4개)에 들어가지 않는다.
    var tabs: some View {
        ChipTabs(
            selection: Binding {
                model.shown
            } set: {
                model.category = $0
            }, options: model.categories.map { ($0, $0.label) })
    }

    var grid: some View {
        let sections = model.sections
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(sections, id: \.category) { section in
                    if model.searching { Caption(section.category.label).padding(.horizontal, Theme.Space.xs) }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: MathPaletteCell.minWidth), spacing: Theme.Space.xs)], spacing: Theme.Space.xs
                    ) {
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
