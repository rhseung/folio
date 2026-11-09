import Foundation

/// The edit view's typing help, as the input guide lists it (#395): what to type and what it gives, by situation.
///
/// Read from the tables the editor itself reads (the catalog's `/` blocks, languages and snippets for the note's math
/// syntax, the callout kinds, the TeX environments, the pairs and list marks, the table keys), so a snippet added in
/// settings or a block added to `/` shows here without another copy. Words are `Phrase`s for the app to say in its
/// language; names already in it (a `/` block's title) and markdown come as they are.
public enum InputGuide {
    public enum Section: String, CaseIterable, Sendable {
        /// Typing opens the completion menu.
        case menu
        /// Tab expands or moves.
        case tab
        /// The editor types along.
        case auto
        /// Keys and the menu in a table.
        case table
    }

    public enum Phrase: String, CaseIterable, Sendable {
        case blocks, link, headingLink, pageLink, embed, calloutKind, codeLanguage, mathSymbols, texEnvironment, asciiMathSymbol
        case nextSlot, indent, pairs, wrap, listContinue, listEnd, tableMenu
        case linkTargets, lastPageFirst, embedTargets, inMath, endWritten, fromTwoLetters, snippet, mathSnippet
        case previousSlot, renumbers, nestedStepsOut, inTable
        case blockList, targetList, headingList, pageList, kindList, languageList, symbolsByCategory, environmentList
        case nextItem, emptyItem, listEnded, selection, secondaryClick
    }

    public enum Words: Equatable, Sendable {
        case phrase(Phrase)
        case table(TableCommand)
        /// Already in the reader's language: a `/` block's title.
        case named(String)
        /// Markdown or a formula, shown in a fixed-width face.
        case code(String)
        /// Names, of which the guide shows the first few (`listed`).
        case list([String])
    }

    public enum Step: Equatable, Sendable {
        case key(String)
        case result(Words)
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String
        public var section: Section
        public var title: Words
        public var note: Words?
        public var steps: [Step]
        /// What else finds it: every name of a list `note` shows only the start of.
        public var keywords: [String]

        public init(_ id: String, _ section: Section, _ title: Words, note: Words? = nil, _ steps: [Step], keywords: [String] = []) {
            self.id = id
            self.section = section
            self.title = title
            self.note = note
            self.steps = steps
            self.keywords = keywords
        }
    }

    /// The `/` menu's item that opens the guide, which the guide leaves out of the blocks it lists.
    public static let menuItemID = "slash.input-guide"
    public static let tab = "⇥"

    /// Everything the guide lists, in its sections' order. `menus` is false where the edit view has no completion menu
    /// (the iPad, #31), `tableMenu` where a table has no menu of commands (also the iPad).
    public static func entries(catalog: CompletionCatalog, menus: Bool = true, tableMenu: Bool = true) -> [Entry] {
        (menus ? menuEntries(catalog) : []) + tabEntries(catalog) + autoEntries() + tableEntries(menu: tableMenu)
    }

    static func menuEntries(_ catalog: CompletionCatalog) -> [Entry] {
        let blocks = catalog.slash.filter { $0.id != menuItemID }
        let languages = catalog.languages + [CBWidget.language]
        var out = [
            Entry("menu.blocks", .menu, .phrase(.blocks), note: .list(blocks.map(\.title)), [.key("/"), .result(.phrase(.blockList))],
                  keywords: blocks.flatMap { [$0.title] + $0.keywords }),
            Entry("menu.link", .menu, .phrase(.link), note: .phrase(.linkTargets), [.key("[["), .result(.phrase(.targetList))]),
            Entry("menu.heading", .menu, .phrase(.headingLink),
                  [.key("[[…#"), .result(.phrase(.headingList)), .key("[[…#^"), .result(.phrase(.blockList))]),
            Entry("menu.page", .menu, .phrase(.pageLink), note: .phrase(.lastPageFirst), [.key("[[…#page="), .result(.phrase(.pageList))]),
            Entry("menu.embed", .menu, .phrase(.embed), note: .phrase(.embedTargets), [.key("![["), .result(.phrase(.targetList))]),
            Entry("menu.callout", .menu, .phrase(.calloutKind), note: .list(CalloutHeader.known), [.key("> [!"), .result(.phrase(.kindList))],
                  keywords: CalloutHeader.known),
            Entry("menu.language", .menu, .phrase(.codeLanguage), note: .list(languages), [.key("```"), .result(.phrase(.languageList))],
                  keywords: languages),
        ]
        // A bare `\` lists them all in either syntax (#392); AsciiMath takes the name in its place.
        out.append(Entry("menu.symbols", .menu, .phrase(.mathSymbols), note: .phrase(.inMath), [.key("\\"), .result(.phrase(.symbolsByCategory))],
                         keywords: catalog.tex ? TeXCommands.all.map(\.name) : AsciiMathSymbols.all.map(\.name)))
        if catalog.tex {
            out += [
                Entry("menu.environment", .menu, .phrase(.texEnvironment), note: .phrase(.endWritten),
                      [.key("\\begin{"), .result(.phrase(.environmentList))], keywords: TeXCommands.environments),
            ]
        } else if let sample = AsciiMathSymbols.all.first(where: { $0.name.count >= 4 }) {
            // A word's first letters, and the names they bring up.
            let typed = String(sample.name.prefix(2))
            // The typed letters can be a name of their own (`fr`); showing it back reads as an echo, not a result.
            let found = Completion.filter(AsciiMathSymbols.items, typed, prefixOnly: true).map(\.title).filter { $0 != typed }
            out.append(Entry("menu.asciimath", .menu, .phrase(.asciiMathSymbol), note: .phrase(.fromTwoLetters),
                             [.key(typed), .result(.list(found))], keywords: AsciiMathSymbols.all.map(\.name)))
        }
        return out
    }

    static func tabEntries(_ catalog: CompletionCatalog) -> [Entry] {
        // Numbered, since settings don't stop two snippets sharing a trigger.
        let snippets = catalog.snippets.enumerated().map { i, s in
            let written = shown(s.body)
            // A snippet that writes what a `/` block does goes by that block's name, as `mk` by 인라인 수식's.
            if !s.inMath, let block = catalog.slash.first(where: { $0.body == s.body }) {
                return Entry("tab.snippet.\(i)", .tab, .named(block.title), note: .phrase(.snippet),
                             [.key(s.trigger), .key(tab), .result(.code(written))], keywords: [s.trigger])
            }
            return Entry("tab.snippet.\(i)", .tab, .code(written), note: .phrase(s.inMath ? .mathSnippet : .snippet),
                         [.key(s.trigger), .key(tab)], keywords: [s.trigger])
        }
        let slot = catalog.tex ? "\\frac{a}{…}" : "frac(a)(…)"
        return snippets + [
            Entry("tab.slot", .tab, .phrase(.nextSlot), note: .phrase(.previousSlot), [.key(tab), .result(.code(slot))]),
            Entry("tab.indent", .tab, .phrase(.indent), note: .phrase(.renumbers), [.key(tab), .key("⇧" + tab)]),
        ]
    }

    static func autoEntries() -> [Entry] {
        let pair = SourceEditing.shownPairs.first ?? "("
        return [
            Entry("auto.pairs", .auto, .phrase(.pairs), note: .code(SourceEditing.shownPairs.joined(separator: " ")),
                  [.key(pair), .result(.code(closed(pair)))], keywords: SourceEditing.shownPairs),
            Entry("auto.wrap", .auto, .phrase(.wrap), note: .code(SourceEditing.shownWraps.joined(separator: " ")),
                  [.result(.phrase(.selection)), .key("$"), .result(.code("$…$"))], keywords: SourceEditing.shownWraps),
            Entry("auto.list", .auto, .phrase(.listContinue), note: .code(SourceEditing.shownListMarks.joined(separator: " ")),
                  [.key("↩"), .result(.phrase(.nextItem))], keywords: SourceEditing.shownListMarks),
            Entry("auto.list-end", .auto, .phrase(.listEnd), note: .phrase(.nestedStepsOut),
                  [.result(.phrase(.emptyItem)), .key("↩"), .result(.phrase(.listEnded))]),
        ]
    }

    static func tableEntries(menu: Bool) -> [Entry] {
        var out: [Entry] = []
        if menu {
            out.append(Entry("table.menu", .table, .phrase(.tableMenu), note: .phrase(.inTable), [.result(.phrase(.secondaryClick))]))
        }
        for command in TableCommand.groups.joined() {
            if let shortcut = command.shortcut {
                out.append(Entry("table.\(command.rawValue)", .table, .table(command), [.key(shortcut.symbols)]))
            } else if menu {
                out.append(Entry("table.\(command.rawValue)", .table, .table(command), [.result(.phrase(.tableMenu))]))
            }
        }
        return out
    }

    /// The entries whose words hold `typed`, ignoring case; `words` says them as the app does.
    public static func filter(_ entries: [Entry], _ typed: String, words: (Words) -> String) -> [Entry] {
        let q = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { entry in
            var said = [words(entry.title)] + (entry.note.map { [words($0)] } ?? []) + entry.keywords
            for step in entry.steps {
                switch step {
                case .key(let k): said.append(k)
                case .result(let w): said.append(words(w))
                }
            }
            return said.contains { $0.lowercased().contains(q) }
        }
    }

    /// The entries in their sections, in the sections' order, leaving out empty ones.
    public static func grouped(_ entries: [Entry]) -> [(section: Section, entries: [Entry])] {
        Section.allCases.compactMap { section in
            let rows = entries.filter { $0.section == section }
            return rows.isEmpty ? nil : (section, rows)
        }
    }

    /// The first few names of a list, and an ellipsis when there are more.
    public static func listed(_ names: [String], first: Int = 4) -> String {
        names.prefix(first).joined(separator: ", ") + (names.count > first ? " …" : "")
    }

    /// A snippet's body on one line with its caret marks as `…`, where one types: `$$1$` as `$…$`.
    public static func shown(_ body: String) -> String {
        let units = Array(body.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < units.count {
            if units[i] == 0x24, i + 1 < units.count, (0x30...0x39).contains(units[i + 1]) {
                out += Array("…".utf16)
                i += 2
                continue
            }
            out.append(units[i] == 0x0A ? 0x20 : units[i])
            i += 1
        }
        return String(utf16CodeUnits: out, count: out.count).trimmingCharacters(in: .whitespaces)
    }

    static func closed(_ opener: String) -> String {
        let closer = String(opener.reversed().map { c in ["(": ")", "[": "]", "{": "}"][c] ?? c })
        return opener + "…" + closer
    }

    /// The fastest way to write what a `/` block puts in, for the menu to show beside it: a snippet that writes the same
    /// (`mk ⇥`), or the block's own markdown when it is short enough to type (`##`, `- [ ]`, `> [!`). Nil for a block
    /// longer than a line or with a place for the caret in it (a table, a template).
    public static func shortcut(for item: CompletionItem, snippets: [Snippet]) -> String? {
        if let snippet = snippets.first(where: { !$0.inMath && $0.body == item.body }) { return snippet.trigger + " " + tab }
        let typed = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains("\n"), shown(typed) == typed else { return nil }
        return typed
    }

    /// The `/` blocks with their shortcut as the detail the menu shows on the right.
    public static func annotated(_ blocks: [CompletionItem], snippets: [Snippet]) -> [CompletionItem] {
        blocks.map { item in
            var item = item
            if item.detail == nil { item.detail = shortcut(for: item, snippets: snippets) }
            return item
        }
    }
}
