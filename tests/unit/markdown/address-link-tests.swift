import Foundation
import Testing

@testable import FolioMarkdown

struct AddressLinkTests {
    let id = UUID(uuidString: "6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41")!

    func page(_ text: String, titles: [UUID: String] = [:], names: [String: String] = [:]) -> String {
        let embeds = NoteEmbeds(
            key: "Host", labels: .init(missing: "MISSING", loop: "LOOP", tooDeep: "DEEP"),
            title: { titles[$0] }, hasNote: { _ in false }, name: { names[$0] }
        ) { _ in nil }
        return HTMLRenderer.blocks(ParsedNote(text), embeds: embeds).map(\.html).joined()
    }

    @Test func anAddressBetweenBracketsIsTheSameLinkAsTheKindAndID() {
        let address = WikiLink.all(in: "[[folio://material/\(id.uuidString)#page=2|슬라이드]]")[0]
        let written = WikiLink.all(in: "[[material:\(id.uuidString)#page=2|슬라이드]]")[0]
        #expect(address.isAddress && address.isAppLink && !address.namesNote)
        #expect(address.objectKind == written.objectKind && address.objectID == written.objectID)
        #expect(address.fragment == written.fragment && address.alias == written.alias && address.href == written.href)
        #expect(WikiLink.all(in: "[[FOLIO://Exam/\(id.uuidString)]]")[0].objectKind == "exam")
    }

    @Test func aNotesAddressNamesTheNoteByIDWithItsHeadingOrBlock() {
        let heading = WikiLink.all(in: "[[folio://note/\(id.uuidString)#%EB%A7%A4%EC%B9%AD]]")[0]
        #expect(heading.noteID == id && heading.fragment == "매칭" && heading.namesNote)
        #expect(heading.href == "folio://note/\(id.uuidString)#매칭")
        let block = WikiLink.all(in: "[[folio://note/\(id.uuidString)#^c1]]")[0]
        #expect(block.noteID == id && block.blockID == "c1" && block.href == "folio://note/\(id.uuidString)#^c1")
    }

    @Test func anAddressWithoutAnObjectIsStillAnAppLink() {
        for written in ["folio://settings/claude", "folio://today", "folio://course/\(id.uuidString)/units"] {
            let link = WikiLink.all(in: "[[\(written)]]")[0]
            #expect(link.isAppLink && !link.namesNote && link.href == written, "\(written)")
        }
        #expect(WikiLink.all(in: "[[folio://course/\(id.uuidString)/units]]")[0].objectID == id)
    }

    @Test func itShowsTheNameTheAppGivesIt() {
        let href = "folio://material/\(id.uuidString)#page=2"
        let html = page("[[\(href)]]", names: [href: "05_Matchings.pdf › 2쪽"])
        #expect(html.contains("<a class=\"wikilink\" href=\"\(href)\">05_Matchings.pdf › 2쪽</a>"), "\(html)")
        #expect(page("[[\(href)|슬라이드]]", names: [href: "05_Matchings.pdf › 2쪽"]).contains(">슬라이드</a>"))
        #expect(page("[[material:\(id.uuidString)#page=2]]", names: [href: "05_Matchings.pdf › 2쪽"]).contains(">05_Matchings.pdf › 2쪽</a>"))
    }

    @Test func anUnnamedAddressShowsItselfAndIsNotBroken() {
        let html = page("[[folio://material/\(id.uuidString)#page=2]]")
        #expect(
            html.contains(
                "<a class=\"wikilink\" href=\"folio://material/\(id.uuidString)#page=2\">folio://material/\(id.uuidString) › page=2</a>"),
            "\(html)")
    }

    @Test func aNotesAddressShowsTheNotesTitle() {
        let html = page("[[folio://note/\(id.uuidString)#%EB%A7%A4%EC%B9%AD]]", titles: [id: "그래프 정리"])
        #expect(html.contains(">그래프 정리 › 매칭</a>"), "\(html)")
    }

    @Test func anEscapedHeadingCantBreakOutOfTheLink() {
        let html = HTMLRenderer.render(markdown: "[[folio://note/\(id.uuidString)#%22%3E%3Cb%3E]]")
        #expect(!html.contains("<b>") && html.contains("&quot;&gt;&lt;b&gt;"), "\(html)")
    }

    @Test func aPastedAddressIsALinkOnlyWhereALinkCanStand() {
        func pastes(_ before: String, _ after: String = "") -> Bool {
            WikiLink.pastesAsLink(in: (before + after) as NSString, at: (before as NSString).length)
        }
        #expect(pastes("") && pastes("시험은 ") && pastes("- ") && pastes("[[앞]] ") && pastes("[글](x) "))
        #expect(!pastes("[[", "]]") && !pastes("보기 [[", "") && !pastes("![[", "]]"))
        #expect(!pastes("[글](", ")") && !pastes("<"))
        #expect(!pastes("`a ", "`"))
        #expect(!pastes("```\n", "\n```"))
        #expect(!pastes("$x", "$"))
    }

    @Test func aBareAddressIsALink() {
        let exam = "folio://exam/\(id.uuidString)"
        #expect(HTMLRenderer.render(markdown: "시험: \(exam).") == "<p>시험: <a href=\"\(exam)\">\(exam)</a>.</p>\n")
        let page = "folio://material/\(id.uuidString)#page=12"
        #expect(HTMLRenderer.render(markdown: "- \(page)").contains("<a href=\"\(page)\">\(page)</a>"))
        #expect(HTMLRenderer.render(markdown: "범위는 \(page).") == "<p>범위는 <a href=\"\(page)\">\(page)</a>.</p>\n")
        let heading = "folio://note/\(id.uuidString)#Intro."
        #expect(HTMLRenderer.render(markdown: heading).contains("<a href=\"\(heading)\">"))
    }

    @Test func aBareAddressInCodeOrAnotherLinkStaysAsItIs() {
        let exam = "folio://exam/\(id.uuidString)"
        #expect(HTMLRenderer.render(markdown: "`\(exam)`") == "<p><code>\(exam)</code></p>\n")
        #expect(HTMLRenderer.render(markdown: "[\(exam)](\(exam))") == "<p><a href=\"\(exam)\">\(exam)</a></p>\n")
        #expect(HTMLRenderer.render(markdown: "[[\(exam)|중간]]") == "<p><a class=\"wikilink\" href=\"\(exam)\">중간</a></p>\n")
        #expect(
            HTMLRenderer.render(markdown: "$\\text{\(exam)}$").contains("<span class=\"math\">")
                && !HTMLRenderer.render(markdown: "$\\text{\(exam)}$").contains("<a "))
    }
}
