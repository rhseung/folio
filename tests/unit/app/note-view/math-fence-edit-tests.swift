import AppKit
import FolioDomain
import FolioMarkdown
import Foundation
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct MathFenceEditTests {
    @Test func aFencesBodyIsMathInItsSyntax() {
        let text = "```am\nsum_(i=1)^n i\n```\n\n$$\nx\n$$"
        let accent = CourseAccent.presets[0].accent
        let storage = SourceStyler(accent: accent, syntax: .latex, baseURL: nil, dark: false).styled(text)
        let ns = text as NSString
        let body = ns.range(of: "sum").location
        #expect(storage.attribute(.noteMathBlock, at: body, effectiveRange: nil) as? String == "sum_(i=1)^n i")
        #expect(storage.mathFence(at: body) == .asciimath)
        #expect(NoteAttributes.same(storage.attribute(.foregroundColor, at: body, effectiveRange: nil), accent.inkNative))
        let dollars = ns.range(of: "x", options: .backwards).location
        #expect(storage.attribute(.noteMathBlock, at: dollars, effectiveRange: nil) as? String == "x")
        #expect(storage.mathFence(at: dollars) == nil)
        let code = SourceStyler(accent: accent, syntax: .latex, baseURL: nil, dark: false).styled("```python\nx = 1\n```")
        #expect(code.attribute(.noteMathBlock, at: 10, effectiveRange: nil) == nil)
    }

    @Test func aTeXFenceInAnAsciiMathNoteTypesTeX() {
        let (view, _) = NoteAssistTests.editor("```tex\n\n```", syntax: .asciimath)
        view.setSelectedRange(NSRange(location: 7, length: 0))
        NoteAssistTests.type(view, "\\fr")
        #expect(view.completion.visible && view.completion.items.contains { $0.title == "\\frac" })
        let (snippet, _) = NoteAssistTests.editor("```tex\n\n```", syntax: .asciimath)
        snippet.setSelectedRange(NSRange(location: 7, length: 0))
        NoteAssistTests.type(snippet, "//")
        NoteAssistTests.tab(snippet)
        #expect(NoteAssistTests.caretShown(snippet) == "```tex\n\\frac{|}{}\n```")
    }

    @Test func anAsciiMathFenceInATeXNoteTypesAsciiMath() {
        let (view, _) = NoteAssistTests.editor("```am\n\n```\n", syntax: .latex)
        view.setSelectedRange(NSRange(location: 6, length: 0))
        NoteAssistTests.type(view, "//")
        NoteAssistTests.tab(view)
        #expect(NoteAssistTests.caretShown(view) == "```am\nfrac(|)()\n```\n")
    }

    @Test func theLanguageMenuOffersTheMathFences() {
        let (view, _) = NoteAssistTests.editor("")
        NoteAssistTests.type(view, "```")
        #expect(Array(view.completion.items.prefix(5).map(\.title)) == ["math", "tex", "latex", "asciimath", "am"])
    }

    @Test func theCaretSaysWhichFenceItIsIn() {
        let (view, _) = NoteAssistTests.editor("```am\nx\n```\n$y$")
        view.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(view.caretFence == .asciimath)
        view.setSelectedRange(NSRange(location: 13, length: 0))
        #expect(view.caretFence == nil)
    }
}
