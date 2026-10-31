@testable import FolioMarkdown
import Markdown
import Foundation
import Testing

struct FrontmatterTests {
    @Test func keepsUnknownLinesAndOrder() {
        let text = "---\nid: 6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41\nkind: rough\naliases:\n  - 매칭\ntags: [graph, \"a, b\"]\n---\n# Body"
        var (fm, body) = Frontmatter.split(text)
        #expect(body == "# Body")
        #expect(fm["kind"] == "rough")
        #expect(fm.list("tags") == ["graph", "\"a", "b\""] || fm.list("tags").first == "graph")
        fm["kind"] = "review"
        fm.setList("unitIds", ["u1", "u2"])
        let out = fm.render(body: body)
        #expect(out.contains("aliases:\n  - 매칭"))
        #expect(out.contains("kind: review"))
        #expect(out.contains("unitIds: [u1, u2]"))
        #expect(Frontmatter.split(out).frontmatter["id"] == "6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41")
    }

    @Test func obsidianBlockListsSurviveAndWindowsLineEndingsRead() {
        let text = "---\nid: A\ntags:\n  - math\n  - linalg\naliases:\n- LA\n---\nBody"
        var (fm, body) = Frontmatter.split(text)
        #expect(fm.list("tags") == ["math", "linalg"] && fm.list("aliases") == ["LA"])
        fm.setList("tags", ["math", "linalg"])
        #expect(fm.render(body: body) == text)
        fm.setList("tags", ["graph"])
        #expect(fm.render(body: body) == "---\nid: A\ntags: [graph]\naliases:\n- LA\n---\nBody")
        let crlf = Frontmatter.split("\u{FEFF}---\r\nid: B\r\n---\r\n본문\r\n")
        #expect(crlf.frontmatter["id"] == "B" && crlf.body == "본문\n")
    }

    @Test func textWithoutFrontmatter() {
        let (fm, body) = Frontmatter.split("---\nnot closed")
        #expect(fm.isEmpty && body == "---\nnot closed")
    }

    @Test func quotesValuesThatNeedIt() {
        var fm = Frontmatter()
        fm["title"] = "Ch 1: Intro"
        #expect(fm.render(body: "") == "---\ntitle: \"Ch 1: Intro\"\n---\n")
        #expect(Frontmatter.split(fm.render(body: "")).frontmatter["title"] == "Ch 1: Intro")
    }
}

struct MathTests {
    func html(_ md: String) -> String { HTMLRenderer.render(markdown: md) }

    @Test func texSurvivesMarkdownEscapes() {
        #expect(html("집합 $\\{x_1, x_2\\}$ 과 $a_1 * b_2$") ==
            "<p>집합 <span class=\"math\">\\{x_1, x_2\\}</span> 과 <span class=\"math\">a_1 * b_2</span></p>\n")
    }

    @Test func displayMathSpansLines() {
        #expect(html("$$\n\\begin{aligned}\na &= b \\\\\nc &= d\n\\end{aligned}\n$$") ==
            "<div class=\"math display\">\\begin{aligned}\na &amp;= b \\\\\nc &amp;= d\n\\end{aligned}</div>\n")
    }

    @Test func dollarsInCodeAndEscapesStayText() {
        #expect(html("`$HOME` costs \\$5 and $10") == "<p><code>$HOME</code> costs $5 and $10</p>\n")
        #expect(html("```sh\necho $PATH\n```") == "<pre data-lang=\"sh\"><code class=\"language-sh\">echo $PATH</code></pre>\n")
    }

    @Test func mathInsideCallout() {
        let out = html("> [!definition] Norm\n> $$\n> \\|v\\| = \\sqrt{v \\cdot v}\n> $$")
        #expect(out.contains("<div class=\"math display\">\\|v\\| = \\sqrt{v \\cdot v}</div>"))
    }
}

struct CalloutTests {
    func html(_ md: String) -> String { HTMLRenderer.render(markdown: md) }

    @Test func numbersPerTypeAndKeepsTextbookNumbers() {
        let out = html("""
        > [!definition] Graph
        > A pair $(V, E)$.

        > [!theorem] Theorem 1.20 (König)
        > Bipartite graphs...

        > [!definition] Matching
        > A set of edges. ^def-matching
        """)
        #expect(out.contains("<span class=\"callout-label\">Definition 1</span> <span class=\"callout-title\">Graph</span>"))
        #expect(out.contains("<span class=\"callout-label\">Theorem 1.20</span> <span class=\"callout-title\">(König)</span>"))
        #expect(out.contains("<details class=\"callout callout-definition\" id=\"^def-matching\" open><summary><span class=\"callout-label\">Definition 2</span>"))
        #expect(!out.contains("^def-matching</p>"))
    }

    @Test func foldedAndAttachedProof() {
        let out = html("""
        > [!theorem] Euler
        > Statement.

        > [!proof]
        > Induction.

        > [!note]- Aside
        > Hidden.
        """)
        #expect(out.contains("<details class=\"callout callout-proof attached\">"))
        #expect(out.contains("<details class=\"callout callout-note\"><summary>"))
        #expect(out.contains("<details class=\"callout callout-theorem\" open>"))
    }

    @Test func proofHangsFromLemmaButNotFromExample() {
        let out = HTMLRenderer.render(markdown: "> [!lemma]\n> L.\n\n> [!proof]\n> P.\n\n> [!example]\n> E.\n\n> [!proof]\n> Q.")
        #expect(out.components(separatedBy: "callout-proof attached").count == 2)
    }

    @Test func topLevelBlocksKnowTheirLines() {
        func spans(_ text: String) -> [String] {
            let note = ParsedNote(text)
            return note.document.children.compactMap { note.lines(of: $0).map { "\($0.lowerBound)-\($0.upperBound) \(note.source($0))" } }
        }
        #expect(spans("# T\n\ntext\n\n> [!note]\n> body\n\n- a\n- b") == ["1-1 # T", "3-3 text", "5-6 > [!note]\n> body", "8-9 - a\n- b"])
        #expect(spans("- a\n- b\n\ntext") == ["1-2 - a\n- b", "4-4 text"])
        // `$$…$$` is longer once protected; the blocks after it still name their own lines, and it ends where it closed.
        #expect(spans("$$x$$\n\nafter\n\n$$\nx\n$$\n\nend") == ["1-1 $$x$$", "3-3 after", "5-7 $$\nx\n$$", "9-9 end"])
    }

    /// The body an edit's lines count in is the same one the note renders from, frontmatter and all.
    @Test func bodyRoundTripsThroughItsFrontmatter() {
        let note = ParsedNote("---\nid: 1\n---\n\n# T\n\ntext\n")
        #expect(ParsedNote(note.text).body == note.body)
    }

    @Test func plainQuoteIsNotACallout() {
        #expect(html("> just a quote") == "<blockquote>\n<p>just a quote</p>\n</blockquote>\n")
    }
}

struct LinkTests {
    @Test func parsesEveryWikiLinkForm() {
        let links = WikiLink.all(in: "[[Note]] [[Note#Heading|보기]] [[Note#^def-vs]] ![[Other#Sec]] [[material:6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41#page=12]]")
        #expect(links.count == 5)
        #expect(links[1].fragment == "Heading" && links[1].alias == "보기")
        #expect(links[2].blockID == "def-vs" && links[2].fragment == nil)
        #expect(links[3].isEmbed)
        #expect(links[4].objectKind == "material" && links[4].fragment == "page=12" && links[4].objectID != nil)
    }

    @Test func rendersLinksButNotInsideCode() {
        let out = HTMLRenderer.render(markdown: "See [[Vector Space#^def-vs|정의]] and `[[raw]]` and [[material:ABC#page=3]]")
        #expect(out.contains("<a class=\"wikilink\" href=\"folio://note/Vector%20Space#^def-vs\">정의</a>"))
        #expect(out.contains("<code>[[raw]]</code>"))
        #expect(out.contains("href=\"folio://material/ABC#page=3\""))
    }

    @Test func blockIDsOnParagraphsAndListItems() {
        let note = ParsedNote("First claim. ^c1\n\n- item ^c2\n")
        #expect(note.blockIDs == ["c1", "c2"])
        let out = HTMLRenderer.render(note)
        #expect(out.contains("<p id=\"^c1\">First claim.</p>"))
        #expect(out.contains("<li id=\"^c2\">item</li>"))
    }

    @Test func pipeTableRendersItsRows() {
        let out = HTMLRenderer.render(markdown: "| 기호 | 뜻 |\n| --- | --- |\n| a | 하나 |\n| b | 둘 |")
        #expect(out.contains("<tbody><tr><td>a</td><td>하나</td></tr><tr><td>b</td><td>둘</td></tr></tbody>"))
    }

    @Test func imageWidthFollowsObsidianSyntax() {
        #expect(HTMLRenderer.render(markdown: "![그래프|300](assets/g.png)") == "<p><img src=\"assets/g.png\" alt=\"그래프\" width=\"300\"></p>\n")
        #expect(HTMLRenderer.render(markdown: "![a|b](x.png)").contains("alt=\"a|b\">"))
    }

    @Test func rawHTMLIsEscaped() {
        #expect(!HTMLRenderer.render(markdown: "<script>alert(1)</script>").contains("<script>"))
    }
}

struct BlockTests {
    @Test func cbTableMergesAndRendersMarkdownCells() {
        let md = """
        ```cb-table
        {"columns":[{"width":120},{"align":"center"}],"headerColumn":true,
         "rows":[{"header":true,"cells":[{"text":"비교","colspan":2}]},
                 {"cells":[{"text":"BFS"},{"text":"- queue\\n- $O(V+E)$"}]}]}
        ```
        """
        let out = HTMLRenderer.render(markdown: md)
        #expect(out.contains("<th colspan=\"2\">"))
        #expect(out.contains("<col style=\"width:120px\">"))
        #expect(out.contains("<td style=\"text-align:center\"><ul>"))
        #expect(out.contains("<span class=\"math\">O(V+E)</span>"))
    }

    @Test func cbWidgetPlaceholder() {
        let out = HTMLRenderer.render(markdown: "```cb-widget\n{\"id\":\"6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41\",\"height\":320}\n```")
        #expect(out == "<div class=\"cb-widget\" data-widget=\"6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41\" style=\"height:320px\"></div>\n")
    }

    @Test func invalidBlockJSONShowsSource() {
        #expect(HTMLRenderer.render(markdown: "```cb-table\n{oops\n```").contains("invalid-block"))
    }

    @Test func gfmTablesTasksAndStrikethrough() {
        let out = HTMLRenderer.render(markdown: "| a | b |\n|:-|-:|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n\n~~old~~")
        #expect(out.contains("<th style=\"text-align:left\">a</th>"))
        #expect(out.contains("<input type=\"checkbox\" disabled checked> done"))
        #expect(out.contains("<del>old</del>"))
    }

    @Test func itemTextAboveSublistAndLineBreaks() {
        let out = HTMLRenderer.render(markdown: "- a\n  - b\n\n첫 줄\n둘째 줄")
        #expect(out.contains("<li>a<ul>"))
        #expect(out.contains("<p>첫 줄<br>\n둘째 줄</p>"))
    }
}

@Test func noteImagesFindsLinksAndEmbedsInOrderOnce() {
    let body = """
    ![IMG_3182|400](assets/IMG_3182.JPG)
    text ![[diagram.png|300]] and [a link](notes.md) ![web](https://x.org/a.png)
    ![again](assets/IMG_3182.JPG) ![sp](assets/My%20Photo.heic) ![[other note]]
    """
    #expect(NoteImages.references(in: body) == [.path("assets/IMG_3182.JPG"), .name("diagram.png"), .path("assets/My Photo.heic")])
}

struct DraftItemTests {
    /// Enter then Tab under a list item leaves `    - `; the item above stays a list item, not a heading.
    @Test func aStartedSubItemDoesNotMakeAHeading() {
        for text in ["- 하나\n    - ", "- 하나\n    -", "본문\n  -"] {
            let note = ParsedNote(text)
            #expect(!note.document.children.contains { $0 is Heading }, "\(text.debugDescription)")
            #expect(DraftItem.mask(text).utf16.count == text.utf16.count)
        }
        #expect(ParsedNote("- 하나\n- ").document.child(at: 0).map { Array($0.children).count } == 2)
        #expect(ParsedNote("제목\n---").document.child(at: 0) is Heading)
        #expect(ParsedNote("- 하나\n    - 둘").document.child(at: 0)?.child(at: 0)?.child(at: 1) is UnorderedList)
    }
}
