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
        /// A word in AsciiMath math: a symbol or function by its AsciiMath name, or a snippet.
        case asciiMath
        /// Inside `[[` or `![[`: what the link points at, or the heading, block or page in it. The app finds the
        /// candidates, which come late (`CompletionMenu.more`).
        case link(LinkQuery)
    }

    public let kind: Kind
    public let text: String
    public let range: NSRange
    public let place: SourcePlace

    /// Whether Return takes the picked candidate. A menu that opened by itself, on a bare fence or a snippet's
    /// trigger, leaves Return a line break, else a fence without a language or a line ending in `->` couldn't be
    /// ended; Tab still takes it.
    public var takesReturn: Bool {
        switch kind {
        case .snippet, .asciiMath: false
        case .codeLanguage: !text.isEmpty
        default: true
        }
    }

    /// The same query narrowed or widened by typing, for which the menu keeps its pick and, while late candidates are
    /// on their way, its rows.
    public func continues(_ other: CompletionQuery) -> Bool {
        guard range.location == other.range.location else { return false }
        if case .link(let a) = kind, case .link(let b) = other.kind { return a.part == b.part && a.target == b.target }
        return kind == other.kind
    }
}

/// The link being written around the caret, `[[target#fragment|alias]]`, as the text has it.
public struct LinkQuery: Equatable, Sendable {
    public enum Part: Equatable, Sendable {
        /// What the link points at, being typed.
        case target
        /// After `#`: a heading of the note.
        case heading
        /// After `#^`: a block of the note.
        case block
        /// After `#page=`: a page of the file.
        case page
    }

    public var part: Part
    public var embed: Bool
    /// A note's title or `<kind>:<ID>`, as written; empty for `.target`, whose typing is the query's text.
    public var target: String
    /// A name already written after `|`, which the link keeps.
    public var alias: String?

    public init(part: Part, embed: Bool = false, target: String = "", alias: String? = nil) {
        self.part = part
        self.embed = embed
        self.target = target
        self.alias = alias
    }
}

/// One candidate in the completion menu. `body` is inserted as a snippet's is: `$1` … mark the caret.
public struct CompletionItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String?
    /// An SF Symbol name.
    public var symbol: String?
    /// A formula shown rendered beside the title, in TeX unless `previewAsciiMath`.
    public var preview: String?
    public var previewAsciiMath: Bool
    /// Other names it is found by, as `table` for 표.
    public var keywords: [String]
    public var body: String
    /// A block of its own, put on a new line when the `/` came after text.
    public var block: Bool
    /// Where the caret goes in `body`, which then goes in as written: a link's title may hold `$1` of its own.
    public var caret: Int?
    /// Leaves the caret where another menu opens, as a file's link does at its page.
    public var continues: Bool

    public init(id: String, title: String, detail: String? = nil, symbol: String? = nil, preview: String? = nil,
                previewAsciiMath: Bool = false, keywords: [String] = [], body: String, block: Bool = false,
                caret: Int? = nil, continues: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.preview = preview
        self.previewAsciiMath = previewAsciiMath
        self.keywords = keywords
        self.body = body
        self.block = block
        self.caret = caret
        self.continues = continues
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
            // Inside a link nothing else is offered: a `/` or a snippet's trigger there is part of a name.
            if let m = prefix.firstMatch(of: #/(!?)\[\[([^\[\]]*)$/#) {
                return link(m.2, embed: m.1 == "!", start: caret - m.2.utf16.count - 2, caret: caret, rest: rest, place: place)
            }
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
        case .math(_, let content):
            guard catalog.tex else {
                // Two letters or more: one letter is a variable, and offering on it would cover every formula.
                if let m = prefix.firstMatch(of: #/(?:^|[^A-Za-z\\])([A-Za-z]{2,})$/#), caret - m.1.utf16.count >= content.location,
                   !asciiMath(String(m.1), catalog: catalog).isEmpty {
                    return make(.asciiMath, m.1)
                }
                if let (snippet, range) = Snippet.match(catalog.snippets, in: text, caret: caret, place: place) {
                    return CompletionQuery(kind: .snippet, text: snippet.trigger, range: range, place: place)
                }
                return nil
            }
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
            return snippets(catalog, trigger: query.text, inMath: query.place.isMath)
        case .asciiMath:
            return asciiMath(query.text, catalog: catalog)
        case .link:
            return []
        }
    }

    // Numbered, since settings don't stop two snippets sharing a trigger and the menu needs distinct ids.
    static func snippets(_ catalog: CompletionCatalog, trigger: String, inMath: Bool) -> [CompletionItem] {
        catalog.snippets.enumerated().filter { $0.element.trigger == trigger && $0.element.inMath == inMath }.map { i, s in
            CompletionItem(id: "snippet.\(i).\(s.trigger)", title: s.trigger, detail: s.expanded.text, symbol: "text.insert", body: s.body)
        }
    }

    /// The snippets `word` triggers, then the symbols whose name starts with it.
    static func asciiMath(_ word: String, catalog: CompletionCatalog) -> [CompletionItem] {
        snippets(catalog, trigger: word, inMath: true) + filter(AsciiMathSymbols.items, word, prefixOnly: true)
    }

    /// The link around the caret. `start` is where its `[[` is and `inner` what is between that and the caret; the rest
    /// of the link after the caret, up to its `]]`, is part of what a candidate replaces.
    static func link(_ inner: Substring, embed: Bool, start: Int, caret: Int, rest: String, place: SourcePlace) -> CompletionQuery? {
        // Past `|` is the name the writer gives the link, which nothing completes.
        guard !inner.contains("|") else { return nil }
        let tail = rest.prefixMatch(of: #/[^\[\]]*\]\]/#).map { String($0.0) }
        let alias = tail.flatMap { t in t.firstIndex(of: "|").map { String(t[t.index(after: $0)...].dropLast(2)) } }
        let range = NSRange(location: start, length: caret - start + (tail?.utf16.count ?? 0))
        func make(_ part: LinkQuery.Part, target: String, typed: Substring) -> CompletionQuery {
            CompletionQuery(kind: .link(LinkQuery(part: part, embed: embed, target: target, alias: alias)), text: String(typed), range: range, place: place)
        }
        guard let hash = inner.firstIndex(of: "#") else { return make(.target, target: "", typed: inner) }
        let target = inner[..<hash].trimmingCharacters(in: .whitespaces)
        let after = inner[inner.index(after: hash)...]
        guard !target.isEmpty else { return nil }
        if after.hasPrefix("^") { return make(.block, target: target, typed: after.dropFirst()) }
        if after.hasPrefix("page=") {
            let digits = after.dropFirst(5)
            return digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? make(.page, target: target, typed: digits) : nil
        }
        return make(.heading, target: target, typed: after)
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
        if let caret = item.caret {
            return SourceEditing.Edit(range: query.range, text: item.body, caret: query.range.location + caret)
        }
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
        case .texCommand, .snippet, .asciiMath, .link:
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

    /// The same query after `n` characters went in (or out, when negative) before it.
    public func shifted(by n: Int) -> CompletionQuery {
        CompletionQuery(kind: kind, text: text, range: NSRange(location: range.location + n, length: range.length), place: place)
    }
}
