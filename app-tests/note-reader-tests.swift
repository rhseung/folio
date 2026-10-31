import FolioDomain
import FolioMarkdown
import Foundation
import Testing
import WebKit
@testable import Folio

/// The read view typed into, laid out by WebKit as in the app: which blocks take typing, and the markdown an edit
/// writes back over the block's lines.
@MainActor @Suite(.serialized)
struct NoteReaderTests {
    static let sample = """
    # 제목

    평범한 문단

    **굵게**와 *기울임*, `코드`, $x^2$, [[다른 노트|별칭]], [링크](https://a.b) ^blk

    첫 줄
    둘째 줄

    - 하나
        - 안쪽
    - [ ] 할 일

    1. 첫째
    2. 둘째

    > [!note] 콜아웃
    > 내용

    | a | b |
    | --- | --- |
    | 1 | 2 |

    ```py
    x = 1
    ```

    $$
    x
    $$
    """

    final class Edits { var all: [(from: Int, to: Int, old: String, new: String)] = [] }

    static func reader(_ text: String, edits: Edits) async throws -> (WKWebView, HTMLView.Coordinator) {
        let html = HTMLRenderer.render(ParsedNote(text), sourceLines: true)
        let page = HTMLView(body: html, edit: { from, to, old, new in edits.all.append((from, to, old, new)); return true })
        let coordinator = page.makeCoordinator()
        let view = page.makeWebView(coordinator)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 3000)
        page.update(view, coordinator, accent: CourseAccent.presets[0].accent)
        for _ in 0..<200 {
            if (try? await js(view, "return !!window.folioReader && !!document.querySelector('[contenteditable]')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        return (view, coordinator)
    }

    static func js(_ view: WKWebView, _ body: String) async throws -> Any? {
        try await view.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .defaultClient)
    }

    static func settle(_ edits: Edits, count: Int) async throws {
        for _ in 0..<100 where edits.all.count < count { try await Task.sleep(for: .milliseconds(20)) }
    }

    /// Paragraphs, headings and lists take typing, with their math, links and block IDs; callouts, tables, code and
    /// display math stay read-only, since the reader can't write them back as written.
    @Test func ordinaryBlocksTakeTyping() async throws {
        let (view, _) = try await Self.reader(Self.sample, edits: Edits())
        let blocks = try await Self.js(view, """
            return [...document.querySelectorAll("body > [data-src]")].map((b) => b.tagName + (b.isContentEditable ? "+" : "-"));
            """) as! [String]
        #expect(blocks == ["H1+", "P+", "P+", "P+", "UL+", "OL+", "DETAILS-", "TABLE-", "PRE-", "DIV-"])
    }

    @Test func editsWriteMarkdownBackOverTheirLines() async throws {
        let edits = Edits()
        let (view, _) = try await Self.reader(Self.sample, edits: edits)
        _ = try await Self.js(view, """
            const [h, plain, rich, two, ul, ol] = document.querySelectorAll("body > [data-src]");
            const { commit } = folioReader.debug;
            plain.append(" 그리고 *별표* 와 a * b");
            commit(plain);
            plain.innerHTML = "1. 첫째<br># 둘째 <b>굵게<br><br>이어서 </b>";
            commit(plain);
            rich.querySelector("em").textContent = "기울인 글";
            commit(rich);
            ul.querySelector("input").dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true }));
            const li = document.createElement("li"); li.textContent = "새 항목"; ul.append(li);
            commit(ul);
            return true;
            """)
        try await Self.settle(edits, count: 5)
        #expect(edits.all.map(\.new) == [
            "평범한 문단 그리고 \\*별표\\* 와 a * b",
            "1\\. 첫째\n\\# 둘째 **굵게**\n\n**이어서** ",
            "**굵게**와 *기울인 글*, `코드`, $x^2$, [[다른 노트|별칭]], [링크](https://a.b) ^blk",
            "- 하나\n    - 안쪽\n- [x] 할 일",
            "- 하나\n    - 안쪽\n- [x] 할 일\n- 새 항목",
        ])
        // Each edit names the lines as they stand after the ones before it: the paragraph grew three.
        #expect(edits.all.map(\.from) == [3, 3, 8, 13, 13])
        #expect(edits.all[2].old == "**굵게**와 *기울임*, `코드`, $x^2$, [[다른 노트|별칭]], [링크](https://a.b) ^blk")
        #expect(edits.all[3].old == "- 하나\n    - 안쪽\n- [ ] 할 일")
    }

    /// The note coming back rendered waits while a block is typed into, so the caret stays; refused edits show it at once.
    @Test func updatesWaitForTheBlockBeingTyped() async throws {
        let (view, _) = try await Self.reader("문단", edits: Edits())
        let result = try await Self.js(view, """
            const p = document.querySelector("p");
            p.focus();
            const typing = document.activeElement === p;
            folioReader.update('<p data-line="1" data-end="1" data-src="새 글">새 글</p>');
            const held = document.querySelector("p").textContent;
            folioReader.update('<p data-line="1" data-end="1" data-src="강제">강제</p>', true);
            return [typing, held, document.querySelector("p").textContent];
            """) as! [Any]
        #expect(result[1] as? String == (result[0] as? Bool == true ? "문단" : "새 글"))
        #expect(result[2] as? String == "강제")
    }
}
