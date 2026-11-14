import Foundation
import PropertyBased
import Testing

@testable import FolioMarkdown

struct NoteOutlineTests {
    let text = """
        ---
        title: 매칭
        ---
        # 매칭

        ## 정의 ^def

        ```python
        # 주석은 제목이 아니다
        ```

        $$
        # x
        $$

        > [!note] 콜아웃
        > # 안쪽 제목

        ### **증강** 경로와 $M \\oplus P$

        #### 깊은 제목

        ##### 더 깊은 제목

        ## [[note:6F1C1C4E-0000-0000-0000-000000000000|베르주]]의 정리[^1]

        [^1]: 각주
        """

    @Test func onlyTheBodysTopLevelHeadingsCount() {
        let outline = NoteOutline(text)
        #expect(outline.entries.map(\.level) == [1, 2, 3, 4, 5, 2])
        #expect(outline.entries.map(\.title) == ["매칭", "정의", "증강 경로와 M \\oplus P", "깊은 제목", "더 깊은 제목", "베르주의 정리"])
        #expect(outline.entries[2].anchor == "**증강** 경로와 $M \\oplus P$")
        #expect(outline.entries[1].id == "정의-^def")
    }

    @Test func linesAndLocationsCountTheFrontmatter() {
        let outline = NoteOutline(text)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for entry in outline.entries {
            #expect(lines[entry.line - 1].hasPrefix(String(repeating: "#", count: entry.level) + " "))
            let rest = (text as NSString).substring(from: entry.location)
            #expect(rest.hasPrefix(String(lines[entry.line - 1])))
        }
        #expect(outline.entries.first?.line == 4)
    }

    @Test func theHeadingReadIsTheLastAtOrAboveTheTopLine() {
        let outline = NoteOutline(text)
        #expect(outline.current(at: 1) == nil)
        #expect(outline.current(at: 4) == 0)
        #expect(outline.current(at: 5) == 0)
        #expect(outline.current(at: outline.entries[1].line) == 1)
        #expect(outline.current(at: 1000) == 5)
    }

    @Test func deepHeadingsFoldUnderTheOneAbove() {
        let outline = NoteOutline(text)
        #expect(outline.owner(of: 3) == 2)
        #expect(outline.owner(of: 4) == 2)
        #expect(outline.owner(of: 2) == nil)
        #expect(outline.folds(2))
        #expect(!outline.folds(1))
        #expect(outline.shown(open: []) == [0, 1, 2, 5])
        #expect(outline.shown(open: [2]) == [0, 1, 2, 3, 4, 5])
        #expect(outline.marked(4, open: []) == 2)
        #expect(outline.marked(4, open: [2]) == 4)
    }

    @Test func indentsSkipLevelsTheNoteDoesntUse() {
        let outline = NoteOutline("## 하나\n\n#### 둘\n\n## 셋")
        let indents = outline.entries.indices.map { outline.indent($0) }
        #expect(indents == [0, 1, 0])
        #expect(NoteOutline("#### 혼자").shown(open: []) == [0])
    }

    @Test func linksToAHeadingGoByTheOutline() {
        let note = ParsedNote(text)
        #expect(note.headings.map(\.text) == NoteOutline(text).entries.map(\.anchor))
        #expect(note.line(heading: "깊은 제목", block: nil) != nil)
    }

    // MARK: [TOC]

    @Test func aTOCLineListsTheHeadingsAsLinks() {
        let html = HTMLRenderer.render(markdown: "# 제목\n\n[TOC]\n\n## 하나\n\n### 안쪽\n\n#### 깊은\n\n## 둘")
        #expect(
            html.contains(
                ##"<nav class="toc"><ul><li><a href="#제목">제목</a><ul><li><a href="#하나">하나</a><ul><li><a href="#안쪽">안쪽</a></li></ul></li><li><a href="#둘">둘</a></li></ul></li></ul></nav>"##
            ))
        #expect(html.contains(#"<h2 id="하나">"#))
        #expect(!html.contains("깊은</a>"))
        #expect(!html.contains("[TOC]"))
    }

    @Test func onlyATOCAloneOnItsLineIsOne() {
        #expect(HTMLRenderer.render(markdown: "## 하나\n\n[toc]").contains("<nav class=\"toc\">"))
        #expect(HTMLRenderer.render(markdown: "## 하나\n\n[TOC] 뒤에 글").contains("[TOC] 뒤에 글"))
        #expect(HTMLRenderer.render(markdown: "## 하나\n\n- [TOC]").contains("<li>[TOC]</li>"))
        #expect(HTMLRenderer.render(markdown: "## 하나\n\n```\n[TOC]\n```").contains("[TOC]"))
        #expect(HTMLRenderer.render(markdown: "[TOC]\n\n본문") == "<p>본문</p>\n")
    }

    @Test func aTOCItemShowsTheHeadingWithoutItsLinks() {
        let html = HTMLRenderer.render(markdown: "[TOC]\n\n## $x^2$와 [[다른 노트|링크]]의 *뜻*[^1] ^abc\n\n[^1]: 각주")
        let card = String(html.prefix { $0 != "\n" })
        #expect(card.contains(#"<span class="math">x^2</span>와 링크의 <em>뜻</em>"#))
        #expect(card.components(separatedBy: "<a ").count == 2)
        let shown = card.replacing(/href="[^"]*"/, with: "")
        #expect(!shown.contains("^abc") && !shown.contains("[^1]"), "\(card)")
    }

    @Test func aTOCInAnEmbedHasNoLinks() {
        let embeds = NoteEmbeds(key: "Host", labels: .init(missing: "MISSING", loop: "LOOP", tooDeep: "DEEP")) { link in
            link.target == "다른" ? NoteEmbeds.Note(key: "다른", text: "## 가\n\n[TOC]\n\n## 나") : nil
        }
        let html = HTMLRenderer.blocks(ParsedNote("![[다른]]"), embeds: embeds).map(\.html).joined()
        #expect(html.contains(#"<nav class="toc"><ul><li><span>가</span></li><li><span>나</span></li></ul></nav>"#))
    }

    // MARK: Properties

    static func note(_ blocks: [Int], levels: [Int]) -> (text: String, headings: [(level: Int, line: Int)]) {
        var rows = ["---", "id: x", "---"]
        var headings: [(Int, Int)] = []
        for (i, kind) in blocks.enumerated() {
            let level = levels[i % levels.count]
            let hashes = String(repeating: "#", count: level)
            switch kind {
            case 0:
                headings.append((level, rows.count + 1))
                rows.append("\(hashes) 제목 \(i)")
            case 1: rows += ["```", "\(hashes) 코드", "```"]
            case 2: rows += ["$$", "\(hashes) x", "$$"]
            case 3: rows += ["> [!note]", "> \(hashes) 안쪽"]
            default: rows.append("문단 \(i)")
            }
            rows.append("")
        }
        return (rows.joined(separator: "\n"), headings)
    }

    @Test func theOutlineIsTheHeadingsWrittenAndNoOtherHashes() async {
        await propertyCheck(input: Gen.int(in: 0...4).array(of: 0...24), Gen.int(in: 1...6).array(of: 1...6)) { blocks, levels in
            let (text, headings) = Self.note(blocks, levels: levels)
            let outline = NoteOutline(text)
            #expect(outline.entries.map(\.level) == headings.map(\.level), "\(text)")
            #expect(outline.entries.map(\.line) == headings.map(\.line), "\(text)")
            let ns = text as NSString
            for entry in outline.entries {
                #expect(ns.substring(from: entry.location).hasPrefix(String(repeating: "#", count: entry.level) + " "))
            }
        }
    }

    @Test func theMarkedHeadingIsAlwaysListed() async {
        await propertyCheck(input: Gen.int(in: 1...6).array(of: 1...16), Gen.int(in: 0...20).array(of: 0...4), Gen.int(in: 0...60)) {
            levels, opened, top in
            let outline = NoteOutline(levels.enumerated().map { "\(String(repeating: "#", count: $1)) 제목 \($0)\n" }.joined(separator: "\n"))
            let open = Set(opened.filter { $0 < levels.count })
            let shown = outline.shown(open: open)
            let shallow = outline.entries.indices.filter { outline.entries[$0].level <= NoteOutline.depth }
            #expect(Set(shallow).isSubset(of: shown))
            if let marked = outline.marked(outline.current(at: top), open: open) { #expect(shown.contains(marked)) }
            #expect((outline.current(at: top) ?? -1) <= (outline.current(at: top + 1) ?? -1))
        }
    }
}
