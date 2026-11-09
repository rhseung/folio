@testable import FolioMarkdown
import Foundation
import Testing

struct MathSymbolsTests {
    let snippets = [Snippet(trigger: "//", body: "\\frac{$1}{$2}", inMath: true), Snippet(trigger: "mk", body: "$$1$", inMath: false)]

    func catalog(tex: Bool) -> CompletionCatalog { CompletionCatalog(snippets: snippets, tex: tex) }

    func query(_ s: String, tex: Bool = true) -> CompletionQuery? {
        let m = Marked(s)
        return Completion.query(in: m.text, caret: m.selection.location, catalog: catalog(tex: tex))
    }

    func accept(_ title: String, _ s: String, tex: Bool) throws -> String {
        let m = Marked(s)
        let q = try #require(Completion.query(in: m.text, caret: m.selection.location, catalog: catalog(tex: tex)))
        let item = try #require(Completion.items(for: q, catalog: catalog(tex: tex)).first { $0.title == title })
        return Marked.show(m.text, Completion.edit(accepting: item, for: q, in: m.text))
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
        #expect(own.category == .snippets && own.items.map(\.title) == ["//"] && own.items[0].preview == "\\frac{a}{b}"
                && own.items[0].detail == "\\frac{}{}")
        #expect(MathSymbols.groups(tex: true, snippets: []).first?.category == .greek)
    }

    @Test func typingNarrowsAcrossCategories() {
        let found = MathSymbols.groups(tex: true, snippets: snippets, matching: "arrow")
        #expect(found.map(\.category) == [.arrows, .fonts])
        #expect(found[0].items.first?.title == "\\rightarrow")
        #expect(MathSymbols.groups(tex: true, snippets: [], matching: "\\subsete").first?.items.first?.title == "\\subseteq")
        #expect(MathSymbols.groups(tex: false, snippets: snippets, matching: "zzz").isEmpty)
    }

    @Test func aBareBackslashOffersEverythingByCategory() throws {
        for tex in [true, false] {
            let q = try #require(query("$x + \\|$", tex: tex))
            #expect(q.kind == .texCommand && q.text.isEmpty && q.range == NSRange(location: 5, length: 1) && q.takesReturn)
            let items = Completion.items(for: q, catalog: catalog(tex: tex))
            #expect(items == MathSymbols.items(tex: tex, snippets: snippets) && items.first?.category == .snippets)
        }
    }

    @Test func anAsciiMathBackslashAsksForNamesAndGoesWithThePick() throws {
        let q = try #require(query("$x \\sub|$", tex: false))
        #expect(q.kind == .texCommand && q.text == "sub" && q.range == NSRange(location: 3, length: 4))
        #expect(Completion.items(for: q, catalog: catalog(tex: false)).map(\.title) == ["sub", "sube"])
        #expect(try accept("sube", "$x \\sub|$", tex: false) == "$x sube|$")
        #expect(try accept("//", "$x \\|$", tex: false) == "$x \\frac{|}{}$")
        // Typed on, the names narrow from the start as TeX's commands do.
        let narrowed = Completion.items(for: try #require(query("$\\al|$", tex: false)), catalog: catalog(tex: false))
        #expect(narrowed.map(\.title) == ["alpha", "aleph"])
        // An escape meant as one: past the space nothing is offered, and outside a formula a `\` is text.
        #expect(query("$x\\ |$", tex: false) == nil)
        #expect(query("a \\|", tex: false) == nil)
        // TeX keeps the `\`, which is the command's own.
        #expect(try accept("\\subseteq", "$x \\subs|$", tex: true) == "$x \\subseteq|$")
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
        // Code takes the name bare.
        #expect(put(alpha, "```tex\n|\n```") == "```tex\n\\alpha|\n```")
        #expect(put(alpha, "`x |`") == "`x \\alpha|`")
        // AsciiMath names are only letters: a space keeps them from the letters beside them.
        let ascii = AsciiMathSymbols.all.first { $0.name == "alpha" }!.item
        #expect(put(ascii, "$2x|$") == "$2x alpha|$")
        #expect(put(ascii, "$2|$") == "$2alpha|$")
    }
}
