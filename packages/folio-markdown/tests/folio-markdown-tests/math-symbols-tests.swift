@testable import FolioMarkdown
import Foundation
import Testing

struct MathSymbolsTests {
    let snippets = [Snippet(trigger: "//", body: "\\frac{$1}{$2}", inMath: true), Snippet(trigger: "mk", body: "$$1$", inMath: false)]

    func catalog(tex: Bool) -> CompletionCatalog { CompletionCatalog(snippets: snippets, tex: tex) }

    func browse(_ s: String, tex: Bool = true) -> CompletionQuery? {
        let m = Marked(s)
        return Completion.symbols(in: m.text, caret: m.selection.location, catalog: catalog(tex: tex))
    }

    @Test func everySymbolHasOneCategory() {
        #expect(TeXCommands.all.allSatisfy { $0.item.category == $0.category })
        #expect(AsciiMathSymbols.all.allSatisfy { $0.item.category == $0.category })
        for tex in [true, false] {
            let groups = MathSymbols.groups(tex: tex, snippets: snippets)
            // Each category once, in the order shown, and nothing of the syntax's lists left out.
            #expect(groups.map(\.category) == MathCategory.allCases)
            let count = tex ? TeXCommands.all.count : AsciiMathSymbols.all.count
            #expect(groups.dropFirst().reduce(0) { $0 + $1.items.count } == count)
            #expect(Set(MathSymbols.items(tex: tex, snippets: snippets).map(\.id)).count == count + 1)
        }
    }

    @Test func eachSyntaxKeepsItsOwnList() throws {
        let tex = MathSymbols.groups(tex: true, snippets: snippets)
        let ascii = MathSymbols.groups(tex: false, snippets: snippets)
        #expect(tex.first { $0.category == .relations }?.items.contains { $0.title == "\\subseteq" } == true)
        #expect(ascii.first { $0.category == .relations }?.items.contains { $0.title == "sube" } == true)
        #expect(tex.first { $0.category == .greek }?.items.first?.title == "\\alpha")
        // Only math snippets, shown by what they write.
        let own = try #require(tex.first)
        #expect(own.category == .snippets && own.items.map(\.title) == ["//"] && own.items[0].preview == "\\frac{}{}")
        #expect(MathSymbols.groups(tex: true, snippets: []).first?.category == .greek)
    }

    @Test func typingNarrowsAcrossCategories() {
        let found = MathSymbols.groups(tex: true, snippets: snippets, matching: "arrow")
        #expect(found.map(\.category) == [.arrows, .fonts])
        #expect(found[0].items.first?.title == "\\rightarrow")
        #expect(MathSymbols.groups(tex: true, snippets: [], matching: "\\subsete").first?.items.first?.title == "\\subseteq")
        #expect(MathSymbols.groups(tex: false, snippets: snippets, matching: "zzz").isEmpty)
    }

    @Test func controlSpaceOpensTheWholeListInAFormula() throws {
        let q = try #require(browse("$x + |$"))
        #expect(q.kind == .mathSymbols && q.text.isEmpty && q.range == NSRange(location: 5, length: 0) && q.takesReturn)
        let items = Completion.items(for: q, catalog: catalog(tex: true))
        #expect(items.first?.category == .snippets && items.count == TeXCommands.all.count + 1)
        #expect(browse("text|") == nil)
        #expect(browse("`$x|$`") == nil)
    }

    @Test func typingAfterwardsNarrowsTheList() throws {
        // With or without the backslash in TeX; the backslash goes too when a pick replaces the word.
        let bare = try #require(browse("$x \\subsete|$"))
        #expect(bare.text == "subsete" && bare.range == NSRange(location: 3, length: 8))
        #expect(Completion.items(for: bare, catalog: catalog(tex: true)).first?.title == "\\subseteq")
        let m = Marked("$x subsete|$")
        let plain = try #require(Completion.symbols(in: m.text, caret: m.selection.location, catalog: catalog(tex: true)))
        let item = try #require(Completion.items(for: plain, catalog: catalog(tex: true)).first)
        #expect(Marked.show(m.text, Completion.edit(accepting: item, for: plain, in: m.text)) == "$x \\subseteq|$")
        // A line break's `\\` starts no name.
        #expect(browse("$$\na \\\\al|\n$$")?.range.length == 2)
        let ascii = try #require(browse("$x in al|$", tex: false))
        #expect(Completion.items(for: ascii, catalog: catalog(tex: false)).first?.title == "alpha")
        // A word that grows is the same query, so the menu keeps its pick; a new word is another.
        #expect(try #require(browse("$x \\su|$")).continues(bare))
        #expect(try #require(browse("$x \\subsete + |$")).continues(bare) == false)
    }

    @Test func paletteInsertsInPlaceOrAsAFormula() {
        let alpha = TeXCommands.all.first { $0.name == "alpha" }!.item
        let frac = TeXCommands.all.first { $0.name == "frac" }!.item
        func put(_ item: CompletionItem, _ s: String) -> String {
            let m = Marked(s)
            return Marked.show(m.text, MathSymbols.insertion(item, in: m.text, selection: m.selection))
        }
        // After a space, before a closing `$` that alone wouldn't close a formula.
        #expect(put(alpha, "$x = |$") == "$x = \\alpha|$")
        #expect(put(alpha, "$|x$") == "$\\alpha| x$")
        #expect(put(frac, "$|$") == "$\\frac{|}{}$")
        // Outside a formula it brings its own.
        #expect(put(alpha, "각 |는") == "각 $\\alpha|$는")
        #expect(put(frac, "«old»") == "$\\frac{|}{}$")
        // AsciiMath names are only letters: a space keeps them from the letters beside them.
        let ascii = AsciiMathSymbols.all.first { $0.name == "alpha" }!.item
        #expect(put(ascii, "$2x|$") == "$2x alpha|$")
        #expect(put(ascii, "$2|$") == "$2alpha|$")
    }
}
