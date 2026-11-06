@testable import FolioMarkdown
import Foundation
import Testing

struct AsciiMathCompletionTests {
    let catalog = CompletionCatalog(snippets: [Snippet(trigger: "sq", body: "sqrt($1)", inMath: true), Snippet(trigger: "mk", body: "$$1$", inMath: false)],
                                    tex: false)

    func query(_ s: String) -> CompletionQuery? {
        let m = Marked(s)
        return Completion.query(in: m.text, caret: m.selection.location, catalog: catalog)
    }

    @Test func aWordInAFormulaOffersSymbols() throws {
        let q = try #require(query("$x in al|$"))
        #expect(q.kind == .asciiMath && q.text == "al" && !q.takesReturn)
        let items = Completion.items(for: q, catalog: catalog)
        #expect(items.first?.title == "alpha" && items.first?.preview == "alpha" && items.first?.previewAsciiMath == true)
        // One letter is a variable; a word no symbol starts with offers nothing; text outside formulas is text.
        #expect(query("$a|$") == nil)
        #expect(query("$qz|$") == nil)
        #expect(query("al|") == nil)
        #expect(query("$\\fr|$") == nil)
        #expect(query("값 mk|")?.kind == .snippet)
    }

    @Test func snippetsComeBeforeSymbols() throws {
        let q = try #require(query("$sq|$"))
        let items = Completion.items(for: q, catalog: catalog)
        #expect(items.first?.id.hasPrefix("snippet.") == true)
        #expect(items.dropFirst().first?.title == "sqrt")
    }

    @Test func argumentsTakeTabThroughTheirBrackets() throws {
        let m = Marked("$fr|$")
        let q = try #require(Completion.query(in: m.text, caret: m.selection.location, catalog: catalog))
        let item = try #require(Completion.items(for: q, catalog: catalog).first { $0.title == "frac" })
        let edit = Completion.edit(accepting: item, for: q, in: m.text)
        #expect(Marked.show(m.text, edit) == "$frac(|)()$")
        let typed = Marked("$frac(a|)()$")
        let next = SourceEditing.tab(typed.text, typed.selection, back: false, asciiMath: true)
        #expect(Marked.show(typed.text, next) == "$frac(a)(|)$")
        // TeX notes keep braces as their slots.
        #expect(Marked.show(typed.text, SourceEditing.tab(typed.text, typed.selection, back: false)) == "$frac(a)()$|")
    }

    @Test func everySymbolIsOfferedOnce() {
        let names = AsciiMathSymbols.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.allSatisfy(\.isLetter) && $0.count >= 2 })
        #expect(AsciiMathSymbols.all.first { $0.name == "root" }?.sample == "root(3)(x)")
    }
}
