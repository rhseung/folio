import FolioDomain
import FolioMarkdown
import SwiftUI

/// Where link completion's candidates come from (the app's search index and files), and what taking one does beyond
/// the text being edited.
@MainActor protocol NoteLinkSource: AnyObject {
    /// `text` is the note as the editor has it, which may be ahead of the file.
    func candidates(for query: CompletionQuery, text: String) async -> [CompletionItem]
    /// Does what a candidate needs before it goes in (a note made, an ID given to a block) and returns what to put in,
    /// with an edit to make first to the note's own text when it is the note whose block gets the ID; nil when it
    /// couldn't be done, and nothing goes in.
    func take(_ item: CompletionItem, for query: CompletionQuery, text: String) -> (item: CompletionItem, own: SourceEditing.Edit?)?
}

/// What the edit view's typing help needs from the app beside the text: the snippets and the note templates, from
/// settings.json, and where link candidates come from.
struct NoteAssist: Equatable {
    var snippets: [MathSnippet] = MathSnippet.defaults
    var asciiSnippets: [MathSnippet] = MathSnippet.asciiMathDefaults
    var templates: [NoteKind: [String]] = [:]
    /// Nil where the note isn't one of a course's, as in tests; links then get no candidates.
    var links: (any NoteLinkSource)?

    init(snippets: [MathSnippet] = MathSnippet.defaults, asciiSnippets: [MathSnippet] = MathSnippet.asciiMathDefaults,
         templates: [NoteKind: [String]] = [:], links: (any NoteLinkSource)? = nil) {
        self.snippets = snippets
        self.asciiSnippets = asciiSnippets
        self.templates = templates
        self.links = links
    }

    init(settings: FolioDomain.Settings, links: (any NoteLinkSource)? = nil) {
        snippets = settings.snippets
        asciiSnippets = settings.asciiSnippets
        templates = Dictionary(uniqueKeysWithValues: NoteAssist.templateKinds.map { ($0, settings.noteSections(for: $0)) })
        self.links = links
    }

    static func == (a: NoteAssist, b: NoteAssist) -> Bool {
        a.snippets == b.snippets && a.asciiSnippets == b.asciiSnippets && a.templates == b.templates && a.links === b.links
    }

    static let templateKinds: [NoteKind] = [.review, .examSummary, .unit]

    /// The snippets outside formulas are the same in either syntax; inside them, each syntax has its own.
    func snippets(syntax: MathSyntax) -> [Snippet] {
        let math = syntax == .latex ? snippets.filter(\.inMath) : asciiSnippets.map { MathSnippet(trigger: $0.trigger, body: $0.body, inMath: true) }
        return (snippets.filter { !$0.inMath } + math).map { Snippet(trigger: $0.trigger, body: $0.body, inMath: $0.inMath) }
    }

    @MainActor func catalog(syntax: MathSyntax) -> CompletionCatalog {
        let snippets = self.snippets(syntax: syntax)
        // Each block with its fastest way in on the right (`##`, `mk ⇥`), so the menu teaches it (#395).
        let blocks = SlashBlocks.items(templates: Self.templateKinds.compactMap { kind in templates[kind].flatMap { $0.isEmpty ? nil : (kind, $0) } })
        return CompletionCatalog(
            slash: InputGuide.annotated(blocks + [SlashBlocks.guide], snippets: snippets),
            languages: NoteScripts.languages + ["mermaid"],
            snippets: snippets,
            tex: syntax == .latex)
    }
}

/// The blocks `/` offers. Their bodies are markdown, and data; their names are the app's.
@MainActor enum SlashBlocks {
    static func items(templates: [(NoteKind, [String])]) -> [CompletionItem] {
        func item(_ id: String, _ title: String, _ symbol: String, _ keywords: String, _ body: String, block: Bool = true) -> CompletionItem {
            CompletionItem(id: "slash.\(id)", title: title, symbol: symbol, keywords: keywords.split(separator: " ").map(String.init), body: body, block: block)
        }
        let fence = "```"
        var out = [
            item("h1", String(localized: .notesAssistHeading(1)), "textformat.size", "heading h1 title", "# "),
            item("h2", String(localized: .notesAssistHeading(2)), "textformat.size", "heading h2", "## "),
            item("h3", String(localized: .notesAssistHeading(3)), "textformat.size", "heading h3", "### "),
            item("bullets", String(localized: .notesAssistBullets), "list.bullet", "list bullet", "- "),
            item("numbers", String(localized: .notesAssistNumbers), "list.number", "list numbered ordered", "1. "),
            item("tasks", String(localized: .notesAssistTasks), "checklist", "todo task checkbox", "- [ ] "),
            item("quote", String(localized: .notesAssistQuote), "text.quote", "quote blockquote", "> "),
            // Left open at `[!`: the callout's type comes next, from the menu that opens there.
            item("callout", String(localized: .notesAssistCallout), "exclamationmark.bubble", "callout admonition", "> [!"),
            item("math", String(localized: .notesAssistMath), "function", "math equation latex display", "$$\n$1\n$$"),
            item("inline-math", String(localized: .notesAssistInlineMath), "x.squareroot", "math inline", "$$1$", block: false),
            // Left open at the fence: the language comes next, from its menu.
            item("code", String(localized: .notesAssistCode), "chevron.left.forwardslash.chevron.right", "code fence", fence),
            item("table", String(localized: .notesAssistTable), "tablecells", "table", "| $1 |  |\n| --- | --- |\n|  |  |"),
            item("widget", String(localized: .notesAssistWidget), "square.on.square", "widget cb-widget",
                 fence + "cb-widget\n{\"id\": \"$1\", \"height\": 320}\n" + fence),
            item("divider", String(localized: .notesAssistDivider), "minus", "divider rule hr", "---\n"),
        ]
        for (kind, sections) in templates {
            let body = sections.enumerated().map { i, s in "## \(s)\n" + (i == 0 ? "$1\n" : "\n") }.joined(separator: "\n")
            out.append(item("template.\(kind.rawValue)", String(localized: .notesAssistTemplate(kind.label)), "doc.text", "template", body))
        }
        return out
    }

    /// Last in the menu: the input guide, which taking puts nothing in but opens the guide (`SourceTextView`).
    static var guide: CompletionItem {
        CompletionItem(id: InputGuide.menuItemID, title: String(localized: .notesGuideTitle), detail: "⌘/", symbol: "keyboard",
                       keywords: ["help", "guide", "shortcut"], body: "")
    }
}

/// The completion menu's state: one query, its candidates and the one picked. Every completion in the edit view
/// goes through it; candidates found later (a search the app runs) are added by `more` when they arrive, and
/// `arrived` tells the view to fit the menu to them.
@MainActor @Observable final class CompletionMenu {
    private(set) var query: CompletionQuery?
    private(set) var items: [CompletionItem] = []
    var selected = 0
    @ObservationIgnored var more: (@MainActor (CompletionQuery) async -> [CompletionItem])?
    @ObservationIgnored var arrived: () -> Void = {}
    @ObservationIgnored private var pending: Task<Void, Never>?

    var visible: Bool { query != nil && !items.isEmpty }
    var current: CompletionItem? { items.indices.contains(selected) ? items[selected] : nil }

    /// A query whose candidates all come late (a link's) keeps the rows of the query it narrows until they come, so
    /// the menu doesn't blink empty on every key.
    func show(_ query: CompletionQuery, _ items: [CompletionItem]) {
        // The pick stays while the same query narrows; a new one starts at the top.
        let same = self.query.map { query.continues($0) } ?? false
        let picked = same ? current?.id : nil
        let waits = items.isEmpty && more != nil && Self.late(query)
        self.query = query
        if !(waits && same) {
            self.items = items
            selected = picked.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        }
        pending?.cancel()
        guard let more, Self.late(query) else { return }
        pending = Task { [weak self] in
            let extra = await more(query)
            guard !Task.isCancelled, let self, self.query == query else { return }
            let picked = self.current?.id
            self.items = items + extra
            self.selected = picked.flatMap { id in self.items.firstIndex { $0.id == id } } ?? 0
            self.arrived()
        }
    }

    /// Queries the text alone has no candidates for.
    static func late(_ query: CompletionQuery?) -> Bool {
        if case .link = query?.kind { true } else { false }
    }

    func hide() {
        pending?.cancel()
        query = nil
        items = []
        selected = 0
    }

    func move(_ by: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + by + items.count) % items.count
    }
}

/// The menu floating by the caret, on glass like everything that floats (docs/DESIGN.md "창 구조").
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
        // A bare `\` lists every symbol of the formula, browsed category by category; once narrowed, best first.
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
                    // The guide is not a block: a line sets it apart, over the row so the menu keeps its height.
                    .overlay(alignment: .top) {
                        if item.id == InputGuide.menuItemID, i > 0 { Theme.Palette.lineSoft.frame(height: 1).padding(.horizontal, Theme.Space.s) }
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
               let picture = NoteMath.shared.picture(formula, syntax: item.previewAsciiMath ? .asciimath : .latex, display: false, size: NoteLook.body,
                                                     dark: scheme == .dark) {
                Image(platformImage: picture.image)
                    .resizable()
                    .frame(width: min(picture.size.width, Self.width / 3), height: min(picture.size.height, Self.rowHeight - Theme.Space.s))
                    .aspectRatio(contentMode: .fit)
            } else if let detail = item.detail {
                // A snippet's detail is what it writes; a link's is where the thing is, in words.
                Text(detail.replacingOccurrences(of: "\n", with: " ")).font(Theme.Typeface.caption).monospaced(!CompletionMenu.late(menu.query))
                    .foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: Self.rowHeight)
        // Concentric with the menu: its corner less the inset the rows sit in.
        .background(selected ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.floating - Self.inset))
    }

    /// For candidates that bring no symbol of their own: what kind of thing they are.
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

extension MathCategory {
    var label: String {
        switch self {
        case .snippets: String(localized: .notesMathCategorySnippets)
        case .greek: String(localized: .notesMathCategoryGreek)
        case .relations: String(localized: .notesMathCategoryRelations)
        case .operators: String(localized: .notesMathCategoryOperators)
        case .arrows: String(localized: .notesMathCategoryArrows)
        case .functions: String(localized: .notesMathCategoryFunctions)
        case .fonts: String(localized: .notesMathCategoryFonts)
        case .symbols: String(localized: .notesMathCategorySymbols)
        }
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
