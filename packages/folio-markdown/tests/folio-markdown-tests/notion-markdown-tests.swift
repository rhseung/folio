@testable import FolioMarkdown
import Testing

struct NotionMarkdownTests {
    @Test func calloutWithBoldTitleBecomesTypedCallout() {
        let notion = """
        <callout icon="⚠️" color="yellow_bg">
        <b>이름 혼동 주의</b>

        2주차의 König's theorem과 다른 정리다. $\\alpha' = \\beta$
        </callout>
        """
        let out = NotionMarkdown.convert(notion)
        #expect(out == "> [!warning] 이름 혼동 주의\n> 2주차의 König's theorem과 다른 정리다. $\\alpha' = \\beta$\n")
        #expect(HTMLRenderer.render(ParsedNote(out)).contains("callout-warning"))
    }

    @Test func calloutWithoutTitleKeepsFirstLine() {
        let out = NotionMarkdown.convert("<callout icon=\"📌\" color=\"blue_bg\">\n아래는 정리한 내용입니다.\n- 목록\n</callout>")
        #expect(out == "> [!info]\n> 아래는 정리한 내용입니다.\n> - 목록\n")
    }

    @Test func toggleBecomesFoldedCallout() {
        let out = NotionMarkdown.convert("<details>\n<summary>증명</summary>\n\t첫 줄\n\t$$\n\tx\n\t$$\n</details>\n뒤")
        #expect(out == "> [!note]- 증명\n> 첫 줄\n> $$\n> x\n> $$\n\n뒤")
    }

    @Test func mentionsImagesAndInlineTags() {
        let id = "3f9c49c761ab80249b61eaae200df7c7"
        let src = "notion-file-block://a/b?name=gt7.svg"
        let text = "필기(<mention url=\"https://app.notion.com/p/\(id)\" />)와 <mention url=\"https://app.notion.com/p/0000000000000000000000000000ffff\" />, <b>굵게</b> <i>기울임</i>\n<image source=\"\(src)\" />\n<image source=\"notion-file-block://missing\" />"
        let out = NotionMarkdown.convert(text, links: [id: "7주차-2"], images: [src: "assets/gt7.svg"])
        #expect(out == "필기([[7주차-2]])와 [링크](https://app.notion.com/p/0000000000000000000000000000ffff), **굵게** *기울임*\n![](assets/gt7.svg)\n")
    }

    @Test func paragraphWrappersAreDropped() {
        let out = NotionMarkdown.convert("2. Claim\n   <p>\n   Hall을 쓴다.\n   </p>")
        #expect(out == "2. Claim\n   Hall을 쓴다.")
    }
}

struct NotionMarkdownBlockTests {
    @Test func htmlTableBecomesMarkdownTable() {
        let notion = "<table header-row=\"true\">\n<colgroup>\n<col width=\"10\" />\n</colgroup>\n<tr>\n<td>\n<b>Case</b>\n</td>\n<td>When</td>\n</tr>\n<tr>\n<td>\n$a|b$\n</td>\n<td>\n둘째\n줄\n</td>\n</tr>\n</table>\n뒤"
        #expect(NotionMarkdown.convert(notion) == "| **Case** | When |\n| --- | --- |\n| $a\\|b$ | 둘째 줄 |\n뒤")
    }

    @Test func quotedObsidianCalloutAndToggle() {
        let notion = "<quote>\n\\[!abstract\\] Stokes’ Theorem\n\n본문\n</quote>\n<toggle>\n강의 자료\n\n<pdf source=\"notion-file-block://p?name=a.pdf\">\n6.1\n</pdf>\n</toggle>"
        let out = NotionMarkdown.convert(notion, images: ["notion-file-block://p?name=a.pdf": "assets/a.pdf"])
        #expect(out == "> [!abstract] Stokes’ Theorem\n> 본문\n\n> [!note]- 강의 자료\n> [a.pdf](assets/a.pdf)\n> 6.1\n")
    }

    @Test func htmlListInsideMarkdownList() {
        let notion = "- 질문\n  <ul>\n  <li>\n  첫째 <b>답</b>\n  </li>\n  <li>\n  둘째\n  </li>\n  </ul>\n<table-of-contents color=\"gray\" />\n<p />"
        #expect(NotionMarkdown.convert(notion) == "- 질문\n  - 첫째 **답**\n  - 둘째")
    }

    @Test func imageWithCaptionOnFollowingLines() {
        let src = "notion-file-block://a?name=b.png"
        #expect(NotionMarkdown.convert("<image source=\"\(src)\">\n그림 1\n</image>", images: [src: "assets/b.png"]) == "![](assets/b.png)\n그림 1")
    }

    @Test func markdownLinksToImportedNotionPagesBecomeWikilinks() {
        let id = "3d4c49c761ab80919f05d57d819e8499"
        let out = NotionMarkdown.convert("필기([2주차](https://app.notion.com/p/\(id)))와 [밖](https://app.notion.com/p/0000000000000000000000000000abcd)", links: [id: "2주차-1"])
        #expect(out == "필기([[2주차-1|2주차]])와 [밖](https://app.notion.com/p/0000000000000000000000000000abcd)")
    }
}
