import Foundation

public enum InputGuide {
    public enum Section: String, CaseIterable, Sendable {
        case menu
        case tab
        case auto
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
        case named(String)
        case code(String)
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

    public static let menuItemID = "slash.input-guide"
    public static let tab = "⇥"

    public static func entries(catalog: CompletionCatalog, menus: Bool = true, tableMenu: Bool = true) -> [Entry] {
        (menus ? menuEntries(catalog) : []) + tabEntries(catalog) + autoEntries() + tableEntries(menu: tableMenu)
    }

    static func menuEntries(_ catalog: CompletionCatalog) -> [Entry] {
        let blocks = catalog.slash.filter { $0.id != menuItemID }
        let languages = catalog.fenceNames
        var out = [
            Entry(
                "menu.blocks", .menu, .phrase(.blocks), note: .list(blocks.map(\.title)), [.key("/"), .result(.phrase(.blockList))],
                keywords: blocks.flatMap { [$0.title] + $0.keywords }),
            Entry("menu.link", .menu, .phrase(.link), note: .phrase(.linkTargets), [.key("[["), .result(.phrase(.targetList))]),
            Entry(
                "menu.heading", .menu, .phrase(.headingLink),
                [.key("[[…#"), .result(.phrase(.headingList)), .key("[[…#^"), .result(.phrase(.blockList))]),
            Entry("menu.page", .menu, .phrase(.pageLink), note: .phrase(.lastPageFirst), [.key("[[…#page="), .result(.phrase(.pageList))]),
            Entry("menu.embed", .menu, .phrase(.embed), note: .phrase(.embedTargets), [.key("![["), .result(.phrase(.targetList))]),
            Entry(
                "menu.callout", .menu, .phrase(.calloutKind), note: .list(CalloutHeader.known),
                [.key("> [!"), .result(.phrase(.kindList))],
                keywords: CalloutHeader.known),
            Entry(
                "menu.language", .menu, .phrase(.codeLanguage), note: .list(languages), [.key("```"), .result(.phrase(.languageList))],
                keywords: languages),
        ]
        out.append(
            Entry(
                "menu.symbols", .menu, .phrase(.mathSymbols), note: .phrase(.inMath), [.key("\\"), .result(.phrase(.symbolsByCategory))],
                keywords: catalog.tex ? TeXCommands.all.map(\.name) : AsciiMathSymbols.all.map(\.name)))
        if catalog.tex {
            out += [
                Entry(
                    "menu.environment", .menu, .phrase(.texEnvironment), note: .phrase(.endWritten),
                    [.key("\\begin{"), .result(.phrase(.environmentList))], keywords: TeXCommands.environments)
            ]
        } else if let sample = AsciiMathSymbols.all.first(where: { $0.name.count >= 4 }) {
            let typed = String(sample.name.prefix(2))
            let found = Completion.filter(AsciiMathSymbols.items, typed, prefixOnly: true).map(\.title).filter { $0 != typed }
            out.append(
                Entry(
                    "menu.asciimath", .menu, .phrase(.asciiMathSymbol), note: .phrase(.fromTwoLetters),
                    [.key(typed), .result(.list(found))], keywords: AsciiMathSymbols.all.map(\.name)))
        }
        return out
    }

    static func tabEntries(_ catalog: CompletionCatalog) -> [Entry] {
        let snippets = catalog.snippets.enumerated().map { i, s in
            let written = shown(s.body)
            if !s.inMath, let block = catalog.slash.first(where: { $0.body == s.body }) {
                return Entry(
                    "tab.snippet.\(i)", .tab, .named(block.title), note: .phrase(.snippet),
                    [.key(s.trigger), .key(tab), .result(.code(written))], keywords: [s.trigger])
            }
            return Entry(
                "tab.snippet.\(i)", .tab, .code(written), note: .phrase(s.inMath ? .mathSnippet : .snippet),
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
            Entry(
                "auto.pairs", .auto, .phrase(.pairs), note: .code(SourceEditing.shownPairs.joined(separator: " ")),
                [.key(pair), .result(.code(closed(pair)))], keywords: SourceEditing.shownPairs),
            Entry(
                "auto.wrap", .auto, .phrase(.wrap), note: .code(SourceEditing.shownWraps.joined(separator: " ")),
                [.result(.phrase(.selection)), .key("$"), .result(.code("$…$"))], keywords: SourceEditing.shownWraps),
            Entry(
                "auto.list", .auto, .phrase(.listContinue), note: .code(SourceEditing.shownListMarks.joined(separator: " ")),
                [.key("↩"), .result(.phrase(.nextItem))], keywords: SourceEditing.shownListMarks),
            Entry(
                "auto.list-end", .auto, .phrase(.listEnd), note: .phrase(.nestedStepsOut),
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

    public static func grouped(_ entries: [Entry]) -> [(section: Section, entries: [Entry])] {
        Section.allCases.compactMap { section in
            let rows = entries.filter { $0.section == section }
            return rows.isEmpty ? nil : (section, rows)
        }
    }

    public static func listed(_ names: [String], first: Int = 4) -> String {
        names.prefix(first).joined(separator: ", ") + (names.count > first ? " …" : "")
    }

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

    public static func shortcut(for item: CompletionItem, snippets: [Snippet]) -> String? {
        if let snippet = snippets.first(where: { !$0.inMath && $0.body == item.body }) { return snippet.trigger + " " + tab }
        let typed = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains("\n"), shown(typed) == typed else { return nil }
        return typed
    }

    public static func annotated(_ blocks: [CompletionItem], snippets: [Snippet]) -> [CompletionItem] {
        blocks.map { item in
            var item = item
            if item.detail == nil { item.detail = shortcut(for: item, snippets: snippets) }
            return item
        }
    }
}
