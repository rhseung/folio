import Foundation
import Testing

@testable import FolioMarkdown

struct NoteIDLinkTests {
    let matching = UUID(uuidString: "6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41")!
    let gone = UUID(uuidString: "0B7A8E0F-3D41-4F5E-9C1D-6F1D2C4E8A3B")!

    func page(_ text: String, _ notes: [UUID: (title: String, text: String)]) -> String {
        let embeds = NoteEmbeds(
            key: "Host", labels: .init(missing: "MISSING", loop: "LOOP", tooDeep: "DEEP"),
            title: { notes[$0]?.title }
        ) { link in
            link.noteID.flatMap { id in notes[id].map { NoteEmbeds.Note(key: id.uuidString, text: $0.text) } }
        }
        return HTMLRenderer.blocks(ParsedNote(text), embeds: embeds).map(\.html).joined()
    }

    @Test func aLinkReadsItsIDHeadingBlockAndName() {
        let link = WikiLink.all(in: "[[note:\(matching.uuidString)#^c1|매칭]]")[0]
        #expect(
            link.noteID == matching && link.blockID == "c1" && link.alias == "매칭" && link.href == "folio://note/\(matching.uuidString)#^c1")
        #expect(WikiLink.all(in: "[[note:\(matching.uuidString)#정의]]")[0].href == "folio://note/\(matching.uuidString)#정의")
        #expect(WikiLink.all(in: "[[매칭]]")[0].noteID == nil)
        #expect(WikiLink.all(in: "[[material:\(matching.uuidString)]]")[0].noteID == nil)
    }

    @Test func aLinkShowsItsNameAndOpensByID() {
        let html = page("[[note:\(matching.uuidString)|매칭 정리]]", [matching: ("10-14(화) 매칭", "")])
        #expect(html.contains("<a class=\"wikilink\" href=\"folio://note/\(matching.uuidString)\">매칭 정리</a>"), "\(html)")
    }

    @Test func aLinkWithoutANameShowsTheTitle() {
        let html = page("[[note:\(matching.uuidString)#정의]]", [matching: ("R&D 매칭", "")])
        #expect(html.contains(">R&amp;D 매칭 › 정의</a>"), "\(html)")
    }

    @Test func aLinkToNoNoteIsBroken() {
        let html = page("[[note:\(gone.uuidString)|옛 노트]]", [:])
        #expect(html.contains("<a class=\"wikilink missing\" href=\"folio://note/\(gone.uuidString)\">옛 노트</a>"), "\(html)")
        let plain = HTMLRenderer.render(markdown: "[[note:\(gone.uuidString)|옛 노트]]")
        #expect(plain.contains("<a class=\"wikilink\" href="), "\(plain)")
    }

    @Test func anEmbedByIDDrawsThePartUnderTheTitle() {
        let html = page("![[note:\(matching.uuidString)#정의]]", [matching: ("매칭", "## 정의\n\n짝짓기 ^c1\n\n## 다음\n\n빠짐")])
        #expect(
            html.contains("<div class=\"embed\"><a class=\"embed-title\" href=\"folio://note/\(matching.uuidString)#정의\">매칭 › 정의</a>"),
            "\(html)")
        #expect(html.contains("짝짓기") && !html.contains("빠짐"))
        #expect(page("![[note:\(gone.uuidString)]]", [:]).contains("MISSING"))
    }

    @Test func aBlockReferenceByIDCarriesItsBlock() {
        let html = page("[[note:\(matching.uuidString)#^c1|정의]]", [matching: ("매칭", "짝짓기 ^c1")])
        #expect(html.contains("<template class=\"ref-preview\"><p>짝짓기</p>\n</template>"), "\(html)")
    }

    @Test func aBlockFollowsMovesWithinItsNoteOnly() {
        let link = "[[note:\(matching.uuidString)#^c1|정의]]\n\n![[note:\(matching.uuidString)#^c1]]"
        let before = page(link, [matching: ("매칭", "# 앞\n\n짝짓기 ^c1\n\n# 뒤")])
        let moved = page(link, [matching: ("매칭", "# 앞\n\n# 뒤\n\n- 목록 안\n- 짝짓기 ^c1")])
        for html in [before, moved] {
            #expect(html.contains("짝짓기") && !html.contains("MISSING"), "\(html)")
        }
        let other = UUID()
        let away = page(link, [matching: ("매칭", "# 앞\n\n# 뒤"), other: ("다른 노트", "짝짓기 ^c1")])
        #expect(away.components(separatedBy: "MISSING").count == 3, "\(away)")
    }

    @Test func aRenameFollowsLinksStillShowingTheOldTitle() {
        let id = matching.uuidString, other = gone.uuidString
        let text =
            "[[note:\(id)|10주차-2]], [[note:\(id)#정의|10주차-2]], ![[note:\(id)#^c1|10주차-2]], [[note:\(id)|내 이름]], [[note:\(id)]], [[note:\(other)|10주차-2]], [[10주차-2]]"
        let out = WikiLink.retitled(text, note: matching, from: "10주차-2", to: "11-05(목) 매칭")
        #expect(
            out
                == "[[note:\(id)|11-05(목) 매칭]], [[note:\(id)#정의|11-05(목) 매칭]], ![[note:\(id)#^c1|11-05(목) 매칭]], [[note:\(id)|내 이름]], [[note:\(id)]], [[note:\(other)|10주차-2]], [[10주차-2]]"
        )
        #expect(WikiLink.retitled(out, note: matching, from: "11-05(목) 매칭", to: "10주차-2") == text)
    }
}

struct MissingTitleLinkTests {
    func page(_ text: String, titles: Set<String>) -> String {
        let embeds = NoteEmbeds(
            key: "Host", labels: .init(missing: "MISSING", loop: "LOOP", tooDeep: "DEEP"),
            hasNote: { titles.contains($0) }
        ) { link in
            titles.contains(link.target) ? NoteEmbeds.Note(key: link.target, text: "본문 ^c1") : nil
        }
        return HTMLRenderer.blocks(ParsedNote(text), embeds: embeds).map(\.html).joined()
    }

    @Test func aTitleNoNoteHasIsBroken() {
        let html = page("[[매칭]] [[매칭 정리|정리]] [[없는 노트#정의]] [[R&D]]", titles: ["매칭", "R&D"])
        #expect(html.contains("<a class=\"wikilink\" href=\"folio://note/%EB%A7%A4%EC%B9%AD\">매칭</a>"), "\(html)")
        #expect(
            html.contains("<a class=\"wikilink missing\" href=\"folio://note/%EB%A7%A4%EC%B9%AD%20%EC%A0%95%EB%A6%AC\">정리</a>"), "\(html)")
        #expect(
            html.contains("<a class=\"wikilink missing\" href=\"folio://note/%EC%97%86%EB%8A%94%20%EB%85%B8%ED%8A%B8#정의\">없는 노트 › 정의</a>"),
            "\(html)")
        #expect(html.contains(">R&amp;D</a>") && !html.contains("missing\" href=\"folio://note/R"), "\(html)")
    }

    @Test func anEmbedOfATitleNoNoteHasIsBroken() {
        let html = page("앞 ![[없음]] 뒤\n\n![[없음]]\n\n![[매칭#^c1]]", titles: ["매칭"])
        #expect(html.contains("<a class=\"embed missing\" href=\"folio://note/%EC%97%86%EC%9D%8C\">없음</a>"), "\(html)")
        #expect(html.contains("<div class=\"embed embed-empty\"><a class=\"embed-title missing\""), "\(html)")
        #expect(html.contains("<a class=\"embed-title\" href=\"folio://note/%EB%A7%A4%EC%B9%AD#^c1\">"), "\(html)")
    }

    @Test func filesAndObjectsAreLeftAlone() {
        let html = page("![[그림.png]] [[slides.pdf]] [[material:\(UUID().uuidString)#page=3]] [[v1.2]]", titles: [])
        #expect(html.components(separatedBy: "missing").count == 2, "\(html)")
        #expect(html.contains("<a class=\"wikilink missing\" href=\"folio://note/v1.2\">v1.2</a>"), "\(html)")
    }

    @Test func withoutNotesNoLinkIsBroken() {
        #expect(!HTMLRenderer.render(markdown: "[[없음]] ![[없음]]").contains("missing"))
    }
}
