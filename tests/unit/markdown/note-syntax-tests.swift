import Foundation
import Testing

@testable import FolioMarkdown

struct NoteSyntaxTests {
    @Test func masksKeepEveryOffset() {
        let text = "Title\n  -\n\n[^1]: note"
        let masked = NoteSyntax.masked(text)
        #expect((masked as NSString).length == (text as NSString).length)
        #expect(masked == Footnotes.mask(DraftItem.mask(text)))
    }

    @Test func spansComeInListOrder() {
        let text = "a [[note]] \\* b[^1] ^id\n\n[^1]: c"
        let kinds = NoteSyntax.spans(in: text, masked: NoteSyntax.masked(text)).map(\.kind)
        #expect(kinds == [.blockID, .escape, .wikiLink(target: "note"), .footnote(definition: false), .footnote(definition: true)])
    }

    @Test func linksInCodeAndMathStayText() {
        let html = HTMLRenderer.render(markdown: "`[[a]]` $[^1]$ [[b]] folio://today\n\n[^1]: x")
        #expect(html.contains("<code>[[a]]</code>"))
        #expect(html.contains("class=\"wikilink\" href=\"b\"") || html.contains(">b</a>"))
        #expect(html.contains("<a href=\"folio://today\">folio://today</a>"))
    }
}
