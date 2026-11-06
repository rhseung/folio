@testable import FolioMarkdown
import Foundation
import Testing

struct FootnoteTests {
    func html(_ md: String) -> String { HTMLRenderer.render(markdown: md) }

    @Test func referencesAreNumberedInTheOrderTheyComeAndListedAtTheEnd() {
        let out = html("둘째[^b]와 첫째[^a], 다시[^b].\n\n[^a]: 에이\n[^b]: 비 *강조*\n\n끝 문단")
        #expect(out.contains("둘째<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\">1</a></sup>"))
        #expect(out.contains("첫째<sup class=\"footnote-ref\"><a href=\"#fn-2\" id=\"fnref-2\">2</a></sup>"))
        #expect(out.contains("다시<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1-2\">1</a></sup>"))
        #expect(out.hasSuffix("""
        <section class="footnotes"><ol>
        <li id="fn-1"><p>비 <em>강조</em> <a class="footnote-back" href="#fnref-1">↩\u{FE0E}</a> <a class="footnote-back" href="#fnref-1-2">↩\u{FE0E}<sup>2</sup></a></p></li>
        <li id="fn-2"><p>에이 <a class="footnote-back" href="#fnref-2">↩\u{FE0E}</a></p></li>
        </ol></section>

        """))
        // The definitions are drawn only in the list; the paragraph after them stays.
        #expect(!out.contains("[^"))
        #expect(out.contains("<p>끝 문단</p>"))
    }

    @Test func aDefinitionThatLooksLikeALinkDefinitionIsStillAFootnote() {
        let out = html("출처[^src]\n\n[^src]: https://example.com")
        #expect(out.contains("<a href=\"#fn-1\" id=\"fnref-1\">1</a>"))
        #expect(out.contains("<li id=\"fn-1\"><p>https://example.com "))
    }

    @Test func labelsMatchIgnoringCaseAndUndefinedOnesStayAsWritten() {
        let out = html("a[^Note] b[^없음]\n\n[^note]: 정의")
        #expect(out.contains("a<sup class=\"footnote-ref\">"))
        #expect(out.contains("b[^없음]"))
        #expect(out.contains("<li id=\"fn-1\"><p>정의 "))
    }

    @Test func anUnreferencedDefinitionIsNotListed() {
        let out = html("본문\n\n[^1]: 혼자")
        #expect(out == "<p>본문</p>\n")
    }

    @Test func codeAndMathKeepTheirBrackets() {
        let out = html("`[^1]` $a[^1]$ 진짜[^1]\n\n```\n[^1]: 코드\n```\n\n[^1]: 각주")
        #expect(out.contains("<code>[^1]</code>"))
        #expect(out.contains("<span class=\"math\">a[^1]</span>"))
        #expect(out.contains("<pre><code>[^1]: 코드</code></pre>"))
        #expect(out.contains("<li id=\"fn-1\"><p>각주 "))
    }

    @Test func referencesInTablesAndCbTablesNumberOnFromTheNote() {
        let md = "앞[^a]\n\n| x |\n| --- |\n| 칸[^b] |\n\n```cb-table\n{\"rows\":[{\"cells\":[{\"text\":\"셀[^c]\"}]}]}\n```\n\n[^a]: A\n[^b]: B\n[^c]: C"
        let out = html(md)
        #expect(out.contains("칸<sup class=\"footnote-ref\"><a href=\"#fn-2\""))
        #expect(out.contains("셀<sup class=\"footnote-ref\"><a href=\"#fn-3\""))
        #expect(out.contains("<li id=\"fn-3\"><p>C "))
    }

    @Test func aFootnoteReferencedOnlyFromAnotherIsListedAfterIt() {
        let out = html("본문[^a]\n\n[^a]: 에이[^b]\n[^b]: 비")
        #expect(out.contains("<li id=\"fn-1\"><p>에이<sup class=\"footnote-ref\"><a href=\"#fn-2\" id=\"fnref-2\">2</a></sup> "))
        #expect(out.contains("<li id=\"fn-2\"><p>비 "))
    }

    @Test func theListIsItsOwnBlockFollowingTheLastDefinition() {
        let note = ParsedNote("# 제목\n\n본문[^1]\n\n[^1]: 각주")
        let blocks = HTMLRenderer.blocks(note)
        #expect(blocks.map(\.html).joined() == HTMLRenderer.render(note))
        #expect(blocks.map(\.lines) == [1...1, 3...3, 5...5, 5...5])
        #expect(blocks[2].html.isEmpty)
        #expect(blocks[3].html.hasPrefix("<section class=\"footnotes\">"))
        // Defined above a block that comes after it on the page, the list follows nothing.
        let early = HTMLRenderer.blocks(ParsedNote("본문[^1]\n\n[^1]: 각주\n\n끝"))
        #expect(early.last?.lines == nil)
    }

    @Test func anEmbedNumbersItsOwnFootnotesWithoutIds() {
        let embeds = NoteEmbeds(key: "Here", labels: .init(missing: "MISSING", loop: "LOOP", tooDeep: "DEEP")) { link in
            link.target == "Other" ? NoteEmbeds.Note(key: "Other", text: "# 절\n\n인용[^x]\n\n# 끝\n\n[^x]: 다른 노트의 각주") : nil
        }
        let blocks = HTMLRenderer.blocks(ParsedNote("![[Other#절]]"), embeds: embeds)
        let out = blocks.map(\.html).joined()
        #expect(out.contains("인용<sup class=\"footnote-ref\">1</sup>"))
        #expect(out.contains("<li><p>다른 노트의 각주</p></li>"))
        #expect(!out.contains("id=\"fn"))
    }

    @Test func maskKeepsLengthAndSkipsFences() {
        let text = "[^1]: a\n```\n[^2]: b\n```\n   [^3]: c\n    [^4]: code"
        let masked = Footnotes.mask(text)
        #expect((masked as NSString).length == (text as NSString).length)
        #expect(masked.split(separator: "\n").map { $0.first == Footnotes.marker || $0.dropFirst(3).first == Footnotes.marker } == [true, false, false, false, true, false])
    }

    @Test func marksFindDefinitionsAndReferencesForTheEditor() {
        let text = "본문[^a] 끝\n[^a]: 뜻[^b]"
        let ns = text as NSString
        let marks = Footnotes.marks(in: text)
        #expect(marks.map { ns.substring(with: $0.range) } == ["[^a]", "[^a]:", "[^b]"])
        #expect(marks.map { ns.substring(with: $0.label) } == ["a", "a", "b"])
        #expect(marks.map(\.definition) == [false, true, false])
    }
}
