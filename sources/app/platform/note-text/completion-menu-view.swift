import FolioDomain
import FolioMarkdown
import SwiftUI

struct CompletionMenuView: View {
    let menu: CompletionMenu
    var pick: (Int) -> Void
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var scheme

    static let width: CGFloat = 288
    static let rowHeight: CGFloat = 32
    static let headerHeight: CGFloat = 24
    static let maxRows = 8
    static let inset = Theme.Space.xs
    static let previewSlot = CGSize(width: width / 3, height: rowHeight + 2 * NoteMath.edge(NoteLook.body))

    static func height(rows: Int) -> CGFloat { CGFloat(min(rows, maxRows)) * rowHeight + 2 * inset }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { rows }
                .overflowFade(.vertical)
                .onChange(of: menu.selected) { _, i in proxy.scrollTo(i) }
        }
        .frame(width: Self.width, height: Self.height(rows: menu.items.count))
        .floatingGlass()
    }

    var rows: some View {
        let sections = menu.query.map { $0.kind == .texCommand && $0.text.isEmpty } ?? false
        let items = menu.items
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if sections, let category = item.category, i == 0 || items[i - 1].category != category {
                    Caption(category.label)
                        .frame(maxWidth: .infinity, minHeight: Self.headerHeight, alignment: .bottomLeading)
                        .padding(.horizontal, Theme.Space.s)
                }
                row(item, selected: i == menu.selected)
                    .overlay(alignment: .top) {
                        if item.id == InputGuide.menuItemID, i > 0 {
                            Theme.Palette.lineSoft.frame(height: 1).padding(.horizontal, Theme.Space.s)
                        }
                    }
                    .id(i)
                    .contentShape(.rect)
                    .onTapGesture { pick(i) }
            }
        }
        .padding(Self.inset)
    }

    func row(_ item: CompletionItem, selected: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: item.symbol ?? symbol)
                .font(Theme.Glyph.regular)
                .foregroundStyle(selected ? accent.ink : Theme.Palette.textTertiary)
                .frame(width: Theme.Size.tile)
            Text(item.title)
                .font(item.title.hasPrefix("\\") || item.previewAsciiMath ? Theme.Typeface.mono : Theme.Typeface.body)
                .foregroundStyle(selected ? accent.ink : Theme.Palette.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            if let formula = item.preview,
                let picture = NoteMath.shared.picture(
                    formula, syntax: item.previewAsciiMath ? .asciimath : .latex, display: false, size: NoteLook.body,
                    dark: scheme == .dark)
            {
                let fitted = picture.fitted(Self.previewSlot)
                Image(platformImage: picture.image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
            } else if let detail = item.detail {
                Text(detail.replacingOccurrences(of: "\n", with: " ")).font(Theme.Typeface.caption).monospaced(
                    !CompletionMenu.late(menu.query)
                )
                .foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Self.rowHeight)
        .background(selected ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.floating - Self.inset))
    }

    var symbol: String {
        switch menu.query?.kind {
        case .callout: "exclamationmark.bubble"
        case .codeLanguage: "chevron.left.forwardslash.chevron.right"
        case .texCommand, .texEnvironment, .asciiMath: "function"
        case .link: "link"
        default: "text.insert"
        }
    }
}
