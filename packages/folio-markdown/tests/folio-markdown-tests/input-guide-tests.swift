@testable import FolioMarkdown
import Foundation
import Testing

/// The input guide and the `/` menu's shortcuts, read from the editor's own tables (#395).
struct InputGuideTests {
    static let slash = [
        CompletionItem(id: "slash.h2", title: "제목 2", keywords: ["heading"], body: "## ", block: true),
        CompletionItem(id: "slash.tasks", title: "할 일", body: "- [ ] ", block: true),
        CompletionItem(id: "slash.callout", title: "콜아웃", body: "> [!", block: true),
        CompletionItem(id: "slash.math", title: "수식 블록", body: "$$\n$1\n$$", block: true),
        CompletionItem(id: "slash.inline-math", title: "인라인 수식", body: "$$1$"),
        CompletionItem(id: "slash.code", title: "코드", body: "```", block: true),
        CompletionItem(id: "slash.table", title: "표", body: "| $1 |  |\n| --- | --- |\n|  |  |", block: true),
        CompletionItem(id: "slash.divider", title: "구분선", body: "---\n", block: true),
        CompletionItem(id: InputGuide.menuItemID, title: "입력 안내", detail: "⌘/", body: ""),
    ]
    static let snippets = [
        Snippet(trigger: "mk", body: "$$1$", inMath: false),
        Snippet(trigger: "dm", body: "$$\n$1\n$$", inMath: false),
        Snippet(trigger: "//", body: "\\frac{$1}{$2}", inMath: true),
        Snippet(trigger: "@a", body: "\\alpha", inMath: true),
    ]
    static let catalog = CompletionCatalog(slash: slash, languages: ["python", "swift"], snippets: snippets, tex: true)

    /// Words as a test reads them: a phrase by its name.
    static func words(_ w: InputGuide.Words) -> String {
        switch w {
        case .phrase(let p): p.rawValue
        case .table(let c): c.rawValue
        case .named(let s), .code(let s): s
        case .list(let names): InputGuide.listed(names)
        }
    }

    @Test func theSlashMenuShowsTheFastestWayToEachBlock() {
        let shown = Dictionary(uniqueKeysWithValues: InputGuide.annotated(Self.slash, snippets: Self.snippets).map { ($0.id, $0.detail) })
        #expect(shown["slash.h2"] == "##")
        #expect(shown["slash.tasks"] == "- [ ]")
        #expect(shown["slash.callout"] == "> [!")
        #expect(shown["slash.inline-math"] == "mk ⇥")
        #expect(shown["slash.math"] == "dm ⇥")
        #expect(shown["slash.code"] == "```")
        #expect(shown["slash.divider"] == "---")
        // Nothing short to type for a table; the guide's own item keeps its key.
        #expect(shown["slash.table"] == .some(nil))
        #expect(shown[InputGuide.menuItemID] == "⌘/")
        // Without the snippet, the block's own markdown has a caret mark in it and so no shortcut.
        #expect(InputGuide.shortcut(for: Self.slash[4], snippets: []) == nil)
    }

    @Test func snippetsComeFromSettingsAndTakeABlocksName() throws {
        let entries = InputGuide.entries(catalog: Self.catalog)
        let mk = try #require(entries.first { $0.keywords == ["mk"] })
        #expect(mk.section == .tab && mk.title == .named("인라인 수식") && mk.steps == [.key("mk"), .key("⇥"), .result(.code("$…$"))])
        let dm = try #require(entries.first { $0.keywords == ["dm"] })
        #expect(dm.steps.last == .result(.code("$$ … $$")))
        let frac = try #require(entries.first { $0.keywords == ["//"] })
        #expect(frac.title == .code("\\frac{…}{…}") && frac.note == .phrase(.mathSnippet) && frac.steps == [.key("//"), .key("⇥")])

        // A snippet added in settings is in the guide too.
        var more = Self.catalog
        more.snippets.append(Snippet(trigger: "iff", body: "\\iff", inMath: true))
        #expect(InputGuide.entries(catalog: more).contains { $0.title == .code("\\iff") && $0.steps.first == .key("iff") })
    }

    @Test func theBlocksRowListsTheSlashMenuButNotItsOwnItem() throws {
        let blocks = try #require(InputGuide.entries(catalog: Self.catalog).first { $0.id == "menu.blocks" })
        #expect(blocks.note == .list(Self.slash.dropLast().map(\.title)))
        #expect(blocks.keywords.contains("heading") && !blocks.keywords.contains("입력 안내"))
        #expect(InputGuide.listed(["a", "b", "c", "d", "e"]) == "a, b, c, d …")
        #expect(InputGuide.listed(["a", "b"]) == "a, b")
    }

    @Test func theMathRowsFollowTheNotesSyntax() {
        let tex = InputGuide.entries(catalog: Self.catalog).map(\.id)
        #expect(tex.contains("menu.tex") && tex.contains("menu.environment") && !tex.contains("menu.asciimath"))
        var ascii = Self.catalog
        ascii.tex = false
        ascii.snippets = [Snippet(trigger: "mk", body: "$$1$", inMath: false), Snippet(trigger: "//", body: "frac($1)($2)", inMath: true)]
        let entries = InputGuide.entries(catalog: ascii)
        #expect(!entries.contains { $0.id == "menu.tex" } && entries.contains { $0.id == "menu.asciimath" })
        #expect(entries.contains { $0.title == .code("frac(…)(…)") })
        #expect(entries.first { $0.id == "tab.slot" }?.steps.last == .result(.code("frac(a)(…)")))
        // The sample's typed letters really bring up the names shown.
        if let row = entries.first(where: { $0.id == "menu.asciimath" }), case .key(let typed) = row.steps[0], case .result(.list(let names)) = row.steps[1] {
            let found = Completion.items(for: CompletionQuery(kind: .asciiMath, text: typed, range: NSRange(), place: .text), catalog: ascii).map(\.title)
            #expect(!names.isEmpty && !names.contains(typed) && names.allSatisfy { found.contains($0) })
        } else {
            Issue.record("no AsciiMath row")
        }
    }

    @Test func withoutAMenuTheGuideLeavesOutWhatOnlyMenusDo() {
        let entries = InputGuide.entries(catalog: Self.catalog, menus: false, tableMenu: false)
        #expect(!entries.contains { $0.section == .menu })
        #expect(!entries.contains { $0.id == "table.menu" || $0.id == "table.format" })
        #expect(entries.contains { $0.id == "table.rowBelow" })
    }

    @Test func everyTableCommandIsListedWithItsKeys() {
        let entries = InputGuide.entries(catalog: Self.catalog).filter { $0.section == .table && $0.id != "table.menu" }
        #expect(entries.map(\.title) == TableCommand.groups.joined().map { .table($0) })
        #expect(entries.first { $0.title == .table(.rowAbove) }?.steps == [.key("⇧⌘↩")])
        #expect(entries.first { $0.title == .table(.moveRowUp) }?.steps == [.key("⌃⌘↑")])
        #expect(entries.first { $0.title == .table(.deleteColumn) }?.steps == [.key("⌥⇧⌘⌫")])
        #expect(Set(TableCommand.allCases) == Set(TableCommand.groups.joined()))
        let keys = TableCommand.allCases.compactMap(\.shortcut)
        #expect(keys.allSatisfy { TableCommand.command(for: $0)?.shortcut == $0 })
    }

    @Test func searchLooksThroughNamesKeysAndLists() {
        let entries = InputGuide.entries(catalog: Self.catalog)
        let ids = { (q: String) in InputGuide.filter(entries, q, words: Self.words).map(\.id) }
        #expect(ids("python") == ["menu.language"])
        #expect(ids("theorem") == ["menu.callout"])
        #expect(ids("HEADING").contains("menu.blocks"))
        #expect(ids("@a").count == 1)
        #expect(ids("⌃⌘").count == 4)
        #expect(ids("  ").count == entries.count)
        #expect(ids("없는말").isEmpty)
        let sections = InputGuide.grouped(entries).map(\.section)
        #expect(sections == InputGuide.Section.allCases)
        #expect(InputGuide.grouped(InputGuide.filter(entries, "python", words: Self.words)).map(\.section) == [.menu])
    }

    /// The pairs, wraps and list marks the guide shows are what typing does.
    @Test func theAutoRowsSayWhatTypingDoes() {
        for opener in SourceEditing.shownPairs {
            var text = "", caret = 0
            for c in opener {
                let edit = SourceEditing.typed(String(c), in: text as NSString, selection: NSRange(location: caret, length: 0))
                    ?? SourceEditing.Edit(range: NSRange(location: caret, length: 0), text: String(c), caret: caret + 1)
                text = edit.applied(to: text as NSString)
                caret = edit.caret
            }
            #expect(text == InputGuide.closed(opener).replacingOccurrences(of: "…", with: ""), "\(opener)")
            #expect(caret == opener.utf16.count, "\(opener)")
        }
        for opener in SourceEditing.shownWraps {
            let wrapped = typing("앞 «말» 뒤", opener)
            #expect(wrapped?.hasPrefix("앞 \(opener)«말»") == true, "\(opener)")
        }
        for mark in SourceEditing.shownListMarks {
            let m = Marked("\(mark) 하나|")
            let next = SourceEditing.newline(m.text, m.selection, inCode: false).map { Marked.show(m.text, $0) }
            #expect((next?.components(separatedBy: "\n").last?.count ?? 0) > 1, "\(mark)")
        }
    }

    @Test func theHintIsForAnEmptyLineOfText() {
        let offers = { (s: String) in
            let m = Marked(s)
            return SourceEditing.offersBlocks(in: m.text, selection: m.selection)
        }
        #expect(offers("|"))
        #expect(offers("# 제목\n\n|"))
        #expect(offers("# 제목\n|\n뒤"))
        #expect(!offers("# 제목|"))
        #expect(!offers("앞 |"))
        #expect(!offers("«앞»"))
        #expect(!offers("```\n|\n```"))
        #expect(!offers("$$\n|\n$$"))
    }

    @Test func aSnippetShowsWhereOneTypes() {
        #expect(InputGuide.shown("$$1$") == "$…$")
        #expect(InputGuide.shown("\\begin{cases}\n$1\n\\end{cases}") == "\\begin{cases} … \\end{cases}")
        #expect(InputGuide.shown("^{2}") == "^{2}")
        #expect(InputGuide.shown("a $ b") == "a $ b")
    }
}
