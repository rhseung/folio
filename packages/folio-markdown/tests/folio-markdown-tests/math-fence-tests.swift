import Foundation
import Testing

@testable import FolioMarkdown

/// A fenced block can choose its formula's syntax (#16): `math`, `tex` and `latex` are TeX, `asciimath` and `am`
/// AsciiMath, whatever the note's; `$$…$$` and `$…$` stay in the note's.
struct MathFenceTests {
    func html(_ s: String) -> String { HTMLRenderer.render(markdown: s) }

    @Test func namesItsSyntax() {
        #expect(MathFence.syntax("math") == .latex && MathFence.syntax("tex") == .latex && MathFence.syntax("latex") == .latex)
        #expect(MathFence.syntax("asciimath") == .asciimath && MathFence.syntax("am") == .asciimath)
        #expect(MathFence.syntax("am title") == .asciimath)
        #expect(MathFence.syntax("python") == nil && MathFence.syntax("") == nil && MathFence.syntax(nil) == nil)
    }

    @Test func aFenceIsDisplayMathInItsSyntax() {
        #expect(
            html("```math\n\\begin{aligned}\na &= b\n\\end{aligned}\n```")
                == "<div class=\"math display\" data-math=\"latex\">\\begin{aligned}\na &amp;= b\n\\end{aligned}</div>\n")
        #expect(html("```tex\nx^2\n```") == "<div class=\"math display\" data-math=\"latex\">x^2</div>\n")
        #expect(html("```latex\nx^2\n```") == "<div class=\"math display\" data-math=\"latex\">x^2</div>\n")
        #expect(html("```asciimath\nsum_(i=1)^n i\n```") == "<div class=\"math display\" data-math=\"asciimath\">sum_(i=1)^n i</div>\n")
        #expect(html("```am\n\"text\" < b\n```") == "<div class=\"math display\" data-math=\"asciimath\">&quot;text&quot; &lt; b</div>\n")
    }

    /// A `$$` block carries no syntax of its own: the page reads the note's.
    @Test func dollarsKeepTheNotesSyntax() {
        #expect(html("$$\nx^2\n$$") == "<div class=\"math display\">x^2</div>\n")
        #expect(html("$x$") == "<p><span class=\"math\">x</span></p>\n")
    }

    @Test func aFenceInACalloutIsMathToo() {
        #expect(html("> [!note] 정리\n> ```am\n> a/b\n> ```").contains("<div class=\"math display\" data-math=\"asciimath\">a/b</div>"))
    }

    /// Claude's `latex` fences are source to copy; `math` was a formula there before fences chose a syntax.
    @Test func anAnswerKeepsTeXFencesAsCode() {
        #expect(
            HTMLRenderer.render(answer: "```latex\n\\section{A}\n```")
                == "<pre data-lang=\"latex\"><code class=\"language-latex\">\\section{A}</code></pre>\n")
        #expect(HTMLRenderer.render(answer: "```math\nx\n```") == "<div class=\"math display\" data-math=\"latex\">x</div>\n")
        #expect(HTMLRenderer.render(answer: "$$\nx\n$$") == "<div class=\"math display\">x</div>\n")
    }

    @Test func blocksFollowTheFenceLines() {
        let note = ParsedNote("앞\n\n```am\na/b\n```\n\n뒤")
        let blocks = HTMLRenderer.blocks(note)
        #expect(blocks.map(\.lines) == [1...1, 3...5, 7...7])
    }
}

struct MathFencePlaceTests {
    func place(_ s: String) -> SourcePlace {
        let m = Marked(s)
        return SourcePlace.at(m.selection.location, in: m.text)
    }

    @Test func aFencesBodyIsMath() {
        #expect(place("```am\nx|\n```") == .math(display: true, content: NSRange(location: 6, length: 1), fence: .asciimath))
        #expect(place("```tex\na\nb|\n```") == .math(display: true, content: NSRange(location: 7, length: 3), fence: .latex))
        #expect(place("```math\n|a\n```").fence == .latex)
        // Left open, it runs to the end, as the markdown parser reads it.
        #expect(place("```am\nx|\ny") == .math(display: true, content: NSRange(location: 6, length: 3), fence: .asciimath))
    }

    @Test func itsFencesAreNot() {
        #expect(place("```math|\nx\n```") == .text)
        #expect(place("```math\nx\n```|") == .code(language: "math"))
        #expect(place("```math\nx\n```\n뒤|") == .text)
        #expect(place("```python\nx|\n```") == .code(language: "python"))
        #expect(place("$$\nx|\n$$").isMath && place("$$\nx|\n$$").fence == nil)
    }
}

struct MathFenceCompletionTests {
    /// A TeX note, whose formulas take `//` as `\frac`; AsciiMath's `//` is `frac()()`.
    let catalog = CompletionCatalog(
        languages: ["python", "latex"],
        snippets: [Snippet(trigger: "mk", body: "$$1$", inMath: false), Snippet(trigger: "//", body: "\\frac{$1}{$2}", inMath: true)],
        tex: true,
        otherMath: [Snippet(trigger: "//", body: "frac($1)($2)", inMath: true)])

    var ascii: CompletionCatalog {
        CompletionCatalog(
            languages: catalog.languages, snippets: catalog.snippets.filter { !$0.inMath } + catalog.otherMath, tex: false,
            otherMath: catalog.snippets.filter(\.inMath))
    }

    func query(_ s: String, _ catalog: CompletionCatalog) -> CompletionQuery? {
        let m = Marked(s)
        return Completion.query(in: m.text, caret: m.selection.location, catalog: catalog)
    }

    func tab(_ s: String, _ catalog: CompletionCatalog) -> String {
        let m = Marked(s)
        return Marked.show(m.text, SourceEditing.tab(m.text, m.selection, back: false, catalog: catalog))
    }

    @Test func theLanguageMenuOffersMathFencesFirst() {
        let names = Completion.items(for: query("```|", catalog)!, catalog: catalog).map(\.title)
        // `latex` is a math fence now, so it isn't offered twice.
        #expect(names == ["math", "tex", "latex", "asciimath", "am", "python", "cb-widget"])
        let m = Marked("```ma|")
        let q = Completion.query(in: m.text, caret: m.selection.location, catalog: catalog)!
        let math = Completion.items(for: q, catalog: catalog).first!
        #expect(Marked.show(m.text, Completion.edit(accepting: math, for: q, in: m.text)) == "```math\n|\n```")
    }

    @Test func aTeXFenceInAnAsciiMathNoteTakesTeX() {
        let command = query("```tex\n\\fr|\n```", ascii)!
        #expect(command.kind == .texCommand)
        #expect(Completion.items(for: command, catalog: ascii).contains { $0.title == "\\frac" })
        #expect(query("```math\n\\begin{al|}\n```", ascii)?.kind == .texEnvironment)
        #expect(tab("```math\n//|\n```", ascii) == "```math\n\\frac{|}{}\n```")
        // Outside the fence the note's syntax holds.
        #expect(query("$\\begin{al|}$", ascii)?.kind != .texEnvironment)
        #expect(tab("$//|$", ascii) == "$frac(|)()$")
    }

    @Test func anAsciiMathFenceInATeXNoteTakesAsciiMath() {
        let word = query("```am\nsu|\n```", catalog)!
        #expect(word.kind == .asciiMath)
        #expect(Completion.items(for: word, catalog: catalog).contains { $0.title == "sum" })
        #expect(tab("```am\n//|\n```", catalog) == "```am\nfrac(|)()\n```")
        // Tab moves on to AsciiMath's next bracket, not to a brace.
        #expect(tab("```am\nfrac(|a)(b)\n```", catalog) == "```am\nfrac(a)(|b)\n```")
        #expect(tab("$//|$", catalog) == "$\\frac{|}{}$")
    }

    @Test func theSameSyntaxChangesNothing() {
        #expect(catalog.at(.math(display: true, content: NSRange(), fence: .latex)).snippets == catalog.snippets)
        #expect(catalog.at(.math(display: true, content: NSRange())).tex)
        #expect(ascii.at(.math(display: true, content: NSRange(), fence: .asciimath)).tex == false)
    }
}
