import Foundation
import Testing

@testable import FolioMarkdown

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

    @Test func dollarsKeepTheNotesSyntax() {
        #expect(html("$$\nx^2\n$$") == "<div class=\"math display\">x^2</div>\n")
        #expect(html("$x$") == "<p><span class=\"math\">x</span></p>\n")
    }

    @Test func aFenceInACalloutIsMathToo() {
        #expect(html("> [!note] 정리\n> ```am\n> a/b\n> ```").contains("<div class=\"math display\" data-math=\"asciimath\">a/b</div>"))
    }

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
        #expect(query("$\\begin{al|}$", ascii)?.kind != .texEnvironment)
        #expect(tab("$//|$", ascii) == "$frac(|)()$")
    }

    @Test func anAsciiMathFenceInATeXNoteTakesAsciiMath() {
        let word = query("```am\nsu|\n```", catalog)!
        #expect(word.kind == .asciiMath)
        #expect(Completion.items(for: word, catalog: catalog).contains { $0.title == "sum" })
        #expect(tab("```am\n//|\n```", catalog) == "```am\nfrac(|)()\n```")
        #expect(tab("```am\nfrac(|a)(b)\n```", catalog) == "```am\nfrac(a)(|b)\n```")
        #expect(tab("$//|$", catalog) == "$\\frac{|}{}$")
    }

    @Test func theSameSyntaxChangesNothing() {
        #expect(catalog.at(.math(display: true, content: NSRange(), fence: .latex)).snippets == catalog.snippets)
        #expect(catalog.at(.math(display: true, content: NSRange())).tex)
        #expect(ascii.at(.math(display: true, content: NSRange(), fence: .asciimath)).tex == false)
    }
}

struct MathSpansTests {
    @Test func splitsInlineAndDisplayMath() {
        #expect(
            MathSpans.split("변 $e$의 수는 $$\\sum_v d(v)/2$$이다")
                == [.text("변 "), .inline("e"), .text("의 수는 "), .display("\\sum_v d(v)/2"), .text("이다")])
    }

    @Test func escapedAndUnclosedDollarsStayText() {
        #expect(MathSpans.split("\\$5와 $3") == [.text("$5와 $3")])
        #expect(MathSpans.split("$a\nb$") == [.text("$a\nb$")])
        #expect(MathSpans.split("$ $") == [.text("$ $")])
        #expect(!MathSpans.hasMath("값은 \\$5") && MathSpans.hasMath("$x$"))
    }
}

// 문제와 카드의 LaTeX 글은 StudyText가 그리기 전에 마크다운과 `$…$`로 바뀐다.
struct LaTeXTextTests {
    @Test func oldMarkdownProblemsStayAsTheyAre() {
        let old = "**굵게**와 *기울임*, $x_1 + y$\n다음 줄"
        #expect(LaTeXText.markdown(old) == old)
    }

    @Test func textCommandsBecomeMarkdown() {
        #expect(LaTeXText.markdown(#"\textbf{정의} \emph{매칭}과 \textit{덮개}, \texttt{code}"#) == "**정의** *매칭*과 *덮개*, `code`")
        #expect(LaTeXText.markdown(#"\underline{밑줄} 50\% \& a\_b"#) == #"밑줄 50% & a\_b"#)
        #expect(LaTeXText.markdown(#"A--B---C ``인용'' a~b"#) == "A\u{2013}B\u{2014}C \u{201C}인용\u{201D} a\u{00A0}b")
        #expect(LaTeXText.markdown(#"첫 줄\\둘째 줄"#) == "첫 줄\n둘째 줄")
    }

    // 수식 안은 KaTeX가 읽으므로 건드리지 않고, `\(…\)`와 `\[…\]`, 수식 환경은 `$`로 바꾼다.
    @Test func mathIsKeptForKaTeX() {
        #expect(LaTeXText.markdown(#"$\textbf{x}_1 -- y$와 \( a^2 \)"#) == #"$\textbf{x}_1 -- y$와 $a^2$"#)
        #expect(LaTeXText.markdown(#"\[ \sum_i x_i \]"#) == #"$$\sum_i x_i$$"#)
        let align = #"\begin{align*} a &= b \\ c &= d \end{align*}"#
        #expect(LaTeXText.markdown(align) == "$$\(align)$$")
        #expect(LaTeXText.markdown(#"\textbf{정리 $K_{3,3}$}"#) == "**정리 $K_{3,3}$**")
    }

    @Test func listsBecomeNumberedLines() {
        let source = #"""
            다음을 구하시오.
            \begin{enumerate}
              \item 최대 매칭
              \item[(b)] 최소
                덮개
              \begin{itemize}
                \item 안쪽
              \end{itemize}
            \end{enumerate}
            끝.
            """#
        #expect(LaTeXText.markdown(source) == "다음을 구하시오.\n1. 최대 매칭\n(b) 최소 덮개\n\u{2003}\u{2022} 안쪽\n끝.")
    }

    @Test func unknownCommandsStayAsSource() {
        #expect(LaTeXText.markdown(#"\hspace{1cm}x \foo"#) == #"\hspace{1cm}x \foo"#)
    }
}
