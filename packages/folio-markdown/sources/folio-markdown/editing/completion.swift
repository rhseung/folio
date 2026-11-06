import Foundation

/// What is being completed at the caret: the kind of thing, what has been typed of it, and what an accepted
/// candidate replaces.
public struct CompletionQuery: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `/` at a line start or after a space: a block to insert.
        case slash
        /// `> [!`: a callout type.
        case callout
        /// An opening code fence: the block's language.
        case codeLanguage
        /// `\` in TeX math: a command.
        case texCommand
        /// `\begin{` in TeX math: an environment, closed with its `\end`.
        case texEnvironment
        /// A snippet's trigger just before the caret.
        case snippet
    }

    public let kind: Kind
    public let text: String
    public let range: NSRange
    public let place: SourcePlace
}

/// One candidate in the completion menu. `body` is inserted as a snippet's is: `$1` … mark the caret.
public struct CompletionItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String?
    /// An SF Symbol name.
    public var symbol: String?
    /// TeX shown rendered beside the title.
    public var preview: String?
    /// Other names it is found by, as `table` for 표.
    public var keywords: [String]
    public var body: String
    /// A block of its own, put on a new line when the `/` came after text.
    public var block: Bool

    public init(id: String, title: String, detail: String? = nil, symbol: String? = nil, preview: String? = nil,
                keywords: [String] = [], body: String, block: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.preview = preview
        self.keywords = keywords
        self.body = body
        self.block = block
    }
}

/// What the menu can offer that the note's text alone doesn't say: the `/` blocks with their names in the app's
/// language, the code languages, the snippets, and whether the note's math is TeX.
public struct CompletionCatalog: Sendable {
    public var slash: [CompletionItem]
    public var languages: [String]
    public var snippets: [Snippet]
    /// TeX commands and math snippets are TeX; an AsciiMath note's formulas have their own short forms.
    public var tex: Bool

    public init(slash: [CompletionItem] = [], languages: [String] = [], snippets: [Snippet] = [], tex: Bool = true) {
        self.slash = slash
        self.languages = languages
        self.snippets = snippets
        self.tex = tex
    }
}

public enum Completion {
    /// The completion the text calls for at the caret, or nil.
    public static func query(in text: NSString, caret: Int, catalog: CompletionCatalog) -> CompletionQuery? {
        let place = SourcePlace.at(caret, in: text)
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let content = SourceLines.content(line, in: text)
        let prefix = text.substring(with: NSRange(location: content.location, length: caret - content.location))
        let rest = text.substring(with: NSRange(location: caret, length: NSMaxRange(content) - caret))
        let next: UInt16? = caret < text.length ? text.character(at: caret) : nil
        func make(_ kind: CompletionQuery.Kind, _ typed: Substring, extra: Int = 0) -> CompletionQuery {
            let n = typed.utf16.count
            return CompletionQuery(kind: kind, text: String(typed), range: NSRange(location: caret - n, length: n + extra), place: place)
        }

        switch place {
        case .text:
            if let m = prefix.wholeMatch(of: #/[ \t]*(?:>[ \t]?)+\[!([A-Za-z-]*)/#) {
                return make(.callout, m.1, extra: next == 0x5D ? 1 : 0)
            }
            if rest.trimmingCharacters(in: .whitespaces).isEmpty, let m = prefix.wholeMatch(of: #/ {0,3}(?:`{3,}|~{3,})([A-Za-z0-9+#._-]*)/#) {
                return make(.codeLanguage, m.1)
            }
            if let m = prefix.firstMatch(of: #/(?:^|[ \t])(\/[\p{L}\p{N}-]*)$/#) {
                return make(.slash, m.1.dropFirst(), extra: 0).widened(by: 1)
            }
            if let (snippet, range) = Snippet.match(catalog.snippets, in: text, caret: caret, place: place) {
                return CompletionQuery(kind: .snippet, text: snippet.trigger, range: range, place: place)
            }
        case .math:
            guard catalog.tex else { return nil }
            if let m = prefix.firstMatch(of: #/\\begin\{([A-Za-z*]*)$/#) {
                return make(.texEnvironment, m.1, extra: next == 0x7D ? 1 : 0)
            }
            if let m = prefix.firstMatch(of: #/(?:^|[^\\])\\([A-Za-z]*)$/#) {
                return make(.texCommand, m.1).widened(by: 1)
            }
            if let (snippet, range) = Snippet.match(catalog.snippets, in: text, caret: caret, place: place) {
                return CompletionQuery(kind: .snippet, text: snippet.trigger, range: range, place: place)
            }
        case .code, .inlineCode:
            break
        }
        return nil
    }

    /// The candidates for `query`, best first.
    public static func items(for query: CompletionQuery, catalog: CompletionCatalog) -> [CompletionItem] {
        switch query.kind {
        case .slash:
            return filter(catalog.slash, query.text)
        case .callout:
            return filter(CalloutHeader.known.map { CompletionItem(id: "callout.\($0)", title: $0, body: $0) }, query.text)
        case .codeLanguage:
            let names = catalog.languages + [CBTable.language, CBWidget.language]
            return filter(names.map { CompletionItem(id: "language.\($0)", title: $0, body: $0) }, query.text)
        case .texCommand:
            return filter(TeXCommands.all.map(\.item), query.text, prefixOnly: true)
        case .texEnvironment:
            return filter(TeXCommands.environments.map { CompletionItem(id: "env.\($0)", title: $0, body: $0) }, query.text, prefixOnly: true)
        case .snippet:
            return catalog.snippets.filter { $0.trigger == query.text && $0.inMath == query.place.isMath }.map { s in
                CompletionItem(id: "snippet.\(s.trigger)", title: s.trigger, detail: s.expanded.text, symbol: "text.insert", body: s.body)
            }
        }
    }

    /// Names that start with what's typed come first, then names that contain it; `prefixOnly` keeps only the first,
    /// as for TeX commands, where a name containing `in` is rarely the one meant.
    public static func filter(_ items: [CompletionItem], _ typed: String, prefixOnly: Bool = false) -> [CompletionItem] {
        let q = typed.lowercased()
        guard !q.isEmpty else { return items }
        func score(_ item: CompletionItem) -> Int? {
            let title = item.title.lowercased(), keys = item.keywords.map { $0.lowercased() }
            let bare = title.hasPrefix("\\") ? String(title.dropFirst()) : title
            if bare.hasPrefix(q) { return bare == q ? 0 : 1 }
            if keys.contains(where: { $0.hasPrefix(q) }) { return 2 }
            if prefixOnly { return nil }
            if bare.contains(q) { return 3 }
            if keys.contains(where: { $0.contains(q) }) { return 4 }
            return nil
        }
        return items.enumerated().compactMap { i, item in score(item).map { (item, $0, i) } }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map(\.0)
    }

    /// The edit that puts `item` in place of what `query` covers.
    public static func edit(accepting item: CompletionItem, for query: CompletionQuery, in text: NSString) -> SourceEditing.Edit {
        var body = item.body
        var range = query.range
        switch query.kind {
        case .callout:
            let after = NSMaxRange(range)
            let spaced = after < text.length && text.character(at: after) == 0x20
            body = item.body + "]" + (spaced ? "" : " ")
        case .codeLanguage:
            if fenceNeedsClosing(text, at: range.location) {
                let line = text.lineRange(for: NSRange(location: range.location, length: 0))
                let fence = text.substring(with: NSRange(location: line.location, length: range.location - line.location)).trimmingCharacters(in: .whitespaces)
                body = item.body + "\n$0\n" + fence
            }
        case .texEnvironment:
            let display: Bool = if case .math(true, _) = query.place { true } else { false }
            body = display ? "\(item.body)}\n$1\n\\end{\(item.body)}" : "\(item.body)} $1 \\end{\(item.body)}"
        case .slash:
            let line = text.lineRange(for: NSRange(location: range.location, length: 0))
            let before = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
            if item.block, !before.trimmingCharacters(in: .whitespaces).isEmpty {
                // The space before `/` would trail the line the block leaves.
                let trailing = before.utf16.count - before.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression).utf16.count
                range = NSRange(location: range.location - trailing, length: range.length + trailing)
                body = "\n" + body
            }
        case .texCommand, .snippet:
            break
        }
        return Snippet(trigger: "", body: body, inMath: false).edit(replacing: range)
    }

    /// An opening fence with no fence after it to close it: the fences after it all pair among themselves.
    static func fenceNeedsClosing(_ text: NSString, at index: Int) -> Bool {
        let line = text.lineRange(for: NSRange(location: index, length: 0))
        guard let open = Fence(text.substring(with: SourceLines.content(line, in: text))) else { return false }
        var count = 0
        var at = NSMaxRange(line)
        while at < text.length {
            let next = text.lineRange(for: NSRange(location: at, length: 0))
            if let f = Fence(text.substring(with: SourceLines.content(next, in: text))), f.char == open.char { count += 1 }
            at = NSMaxRange(next)
        }
        return count % 2 == 0
    }
}

extension CompletionQuery {
    /// The same query reaching `n` more characters back, over the `/` or `\` that started it.
    func widened(by n: Int) -> CompletionQuery {
        CompletionQuery(kind: kind, text: text, range: NSRange(location: range.location - n, length: range.length + n), place: place)
    }
}
