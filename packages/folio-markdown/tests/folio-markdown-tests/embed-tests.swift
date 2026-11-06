@testable import FolioMarkdown
import Foundation
import Testing

/// Notes found by title, as the app finds them in a course.
private func embeds(_ notes: [String: String], own: String? = "Host", math: [String: String] = [:]) -> NoteEmbeds {
    NoteEmbeds(key: own, labels: .init(missing: "MISSING", loop: "LOOP", tooDeep: "DEEP")) { link in
        notes[link.target].map { NoteEmbeds.Note(key: link.target, text: $0, math: math[link.target]) }
    }
}

private func page(_ text: String, _ notes: [String: String], own: String? = "Host", math: [String: String] = [:]) -> String {
    HTMLRenderer.blocks(ParsedNote(text), embeds: embeds(notes, own: own, math: math)).map(\.html).joined()
}

struct NoteSectionTests {
    let note = ParsedNote("""
    ---
    id: x
    ---
    # 매칭

    소개

    ## 정의

    짝짓기는 간선 집합이다. ^def

    ### 예시

    - 하나
        - 안쪽 ^inner
    - 둘 ^two

    ## 정리

    > [!theorem] 베르주
    > 증강 경로가 없다. ^berge

    끝
    """)

    @Test func aHeadingRunsToTheNextOneAsHigh() {
        #expect(note.section(heading: "정의", block: nil) == "## 정의\n\n짝짓기는 간선 집합이다. ^def\n\n### 예시\n\n- 하나\n    - 안쪽 ^inner\n- 둘 ^two")
        #expect(note.section(heading: "정리", block: nil) == "## 정리\n\n> [!theorem] 베르주\n> 증강 경로가 없다. ^berge\n\n끝")
        // Obsidian matches the heading's text ignoring case.
        #expect(note.section(heading: " 예시 ", block: nil)?.hasPrefix("### 예시\n") == true)
        #expect(note.section(heading: "없는 제목", block: nil) == nil)
    }

    @Test func aBlockIsItsParagraphItemOrCallout() {
        #expect(note.section(heading: nil, block: "def") == "짝짓기는 간선 집합이다. ^def")
        #expect(note.section(heading: nil, block: "inner") == "- 안쪽 ^inner")
        #expect(note.section(heading: nil, block: "two") == "- 둘 ^two")
        #expect(note.section(heading: nil, block: "berge") == "> [!theorem] 베르주\n> 증강 경로가 없다. ^berge")
        #expect(note.section(heading: nil, block: "nope") == nil)
    }

    @Test func noFragmentIsTheWholeBody() {
        #expect(note.section(heading: nil, block: nil) == note.body)
    }
}

struct EmbedTests {
    @Test func anEmbedDrawsThePartItPointsAt() {
        let html = page("앞\n\n![[Other#정의]]\n\n뒤", ["Other": "# 제목\n\n## 정의\n\n내용 **굵게** ^c1\n\n## 다음\n\n빠짐"])
        #expect(html.contains("<div class=\"embed\"><a class=\"embed-title\" href=\"folio://note/Other#정의\">Other › 정의</a>"), "\(html)")
        #expect(html.contains("<h2>정의</h2>") && html.contains("<p>내용 <strong>굵게</strong></p>"), "\(html)")
        #expect(!html.contains("빠짐"))
        // Ids would repeat the other note's, which a link to this note's heading or block would scroll to.
        #expect(!html.contains("id=\"^c1\"") && !html.contains("id=\"정의\""))
    }

    @Test func aBlockEmbedDrawsTheBlock() {
        let html = page("![[Other#^c1]]", ["Other": "위\n\n- 항목 ^c1\n- 다른 항목"])
        #expect(html.contains("<li>항목</li>") && !html.contains("다른 항목"), "\(html)")
    }

    @Test func anEmbedWithTextAroundItStaysALink() {
        let html = page("보기: ![[Other]] 참고", ["Other": "내용"])
        #expect(html.contains("<a class=\"embed\" href=\"folio://note/Other\">Other</a>") && !html.contains("내용"), "\(html)")
    }

    @Test func embedsOnTheirOwnLinesAreBlocksInOrder() {
        let html = page("![[A]]\n![[B]]", ["A": "에이", "B": "비"])
        let a = try! #require(html.range(of: "에이")), b = try! #require(html.range(of: "비"))
        #expect(a.lowerBound < b.lowerBound && !html.contains("<p><div"), "\(html)")
    }

    @Test func aMissingNoteOrHeadingSaysSo() {
        #expect(page("![[Gone]]", [:]).contains("<div class=\"embed embed-empty\"><a class=\"embed-title\" href=\"folio://note/Gone\">Gone</a><p class=\"embed-note\">MISSING</p></div>"))
        #expect(page("![[Other#없음]]", ["Other": "# 있음"]).contains("MISSING"))
    }

    @Test func aNoteInsideItselfIsDrawnOnce() {
        // Host embeds A, which embeds B, which embeds A again; and a note embedding itself.
        let html = page("![[A]]", ["A": "에이\n\n![[B]]", "B": "비\n\n![[A]]"])
        #expect(html.components(separatedBy: "에이").count == 2 && html.components(separatedBy: "LOOP").count == 2, "\(html)")
        #expect(page("![[Host]]", ["Host": "![[Host]]"], own: "Host").contains("LOOP"))
        // A section of the note itself is not a loop until it holds the embed again.
        #expect(!page("![[Host#끝]]\n\n# 끝\n\n마지막", ["Host": "![[Host#끝]]\n\n# 끝\n\n마지막"]).contains("LOOP"))
    }

    @Test func aChainStopsAtTheDepthLimit() {
        let notes = Dictionary(uniqueKeysWithValues: (0...9).map { ("N\($0)", "층 \($0)\n\n![[N\($0 + 1)]]") })
        let html = page("![[N0]]", notes)
        #expect(html.contains("층 \(NoteEmbeds.depth - 1)") && !html.contains("층 \(NoteEmbeds.depth)"), "\(html)")
        #expect(html.contains("DEEP"))
    }

    @Test func anEmbeddedNoteKeepsItsMathSyntax() {
        #expect(page("![[A]]", ["A": "$x$"], math: ["A": "asciimath"]).contains("<div class=\"embed\" data-math=\"asciimath\">"))
    }

    /// Images and other files are not notes, and keep the link they had.
    @Test func filesAreNotDrawnAsNotes() {
        #expect(page("![[그림.png]]", ["그림.png": "x"]).contains("<a class=\"embed\" href="))
        #expect(page("![[v1.2]]", ["v1.2": "버전"]).contains("버전"))
    }

    @Test func withoutEmbedsTheLinkStays() {
        let html = HTMLRenderer.blocks(ParsedNote("![[Other]]")).map(\.html).joined()
        #expect(html == "<p><a class=\"embed\" href=\"folio://note/Other\">Other</a></p>\n")
    }
}

struct BlockReferencePreviewTests {
    @Test func aReferenceCarriesItsBlock() {
        let html = page("본문 [[Other#^c1|보기]] 끝 ^mine", ["Other": "위\n\n정의 $x$ ^c1\n\n아래"], math: ["Other": "latex"])
        #expect(html.contains("<a class=\"wikilink\" href=\"folio://note/Other#^c1\">보기</a><template class=\"ref-preview\" data-math=\"latex\"><p>정의 <span class=\"math\">x</span></p>\n</template> 끝"), "\(html)")
        // The paragraph keeps its own block ID.
        #expect(html.hasPrefix("<p id=\"^mine\">"))
    }

    @Test func aMissingBlockSaysSo() {
        #expect(page("[[Other#^gone]]", ["Other": "x"]).contains("<template class=\"ref-preview\"><p class=\"embed-note\">MISSING</p></template>"))
    }

    /// Only block references: a heading link or a whole note opens without a preview.
    @Test func otherLinksCarryNothing() {
        #expect(!page("[[Other#제목]] [[Other]] [[material:6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41#page=2]]", ["Other": "# 제목"]).contains("template"))
    }

    /// A preview's own references get none, so a block naming itself is drawn once.
    @Test func previewsDoNotNest() {
        let html = page("[[A#^a]]", ["A": "에이 [[A#^a]] ^a"])
        #expect(html.components(separatedBy: "<template").count == 2, "\(html)")
    }

    @Test func aTitleWithAnAmpersandIsFound() {
        #expect(page("[[R&D#^x]]", ["R&D": "찾음 ^x"]).contains("찾음"))
    }
}
