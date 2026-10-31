import FolioDomain
import FolioMarkdown
import Foundation
import Testing
import WebKit
@testable import Folio

/// The live-preview editor laid out by WebKit, as in the app: it reads like the reader (note.css), and the caret moves
/// nothing it shouldn't. Each failure names the line and how far it moved, so a fix can start from the report.
@MainActor @Suite(.serialized)
struct NoteLayoutTests {
    static let sample = """
    # 그래프 이론 3주차

    오일러 경로는 **모든 간선**을 한 번씩 지나는 경로다. 차수가 홀수인 정점은 $0$개 또는 $2$개여야 하고, 이 조건은 연결 그래프에서 충분조건이기도 하다.

    ## 정의

    > [!definition] 오일러 경로
    > 모든 간선을 정확히 한 번 지나는 경로.

    > [!theorem] 오일러
    > 연결 그래프 $G$에 오일러 회로가 있을 필요충분조건은 모든 정점의 차수가 짝수인 것이다.

    > [!proof]
    > 회로를 따라가면 정점에 들어온 만큼 나간다.

    > [!example] 두 문단
    > 첫 문단은 한 줄이고
    > 줄을 바꿔 이어진다.
    >
    > 둘째 문단.

    ## 예시

    - 쾨니히스베르크의 다리
    - 한붓그리기
        - 시작점과 끝점이 같은 경우
        - 다른 경우
    - [ ] 연습문제 3번
    - [x] 연습문제 1번

    1. 차수를 센다
    2. 홀수 차수 정점을 찾는다

    - 느슨한 목록의 첫 항목

    - 빈 줄 뒤의 둘째 항목

    $$
    \\sum_{v \\in V} \\deg(v) = 2|E|
    $$

    | 그래프 | 정점 | 간선 |
    | --- | :---: | ---: |
    | $K_4$ | 4 | 6 |
    | $C_5$ | 5 | 5 |

    ```python
    def degree(g, v):
        return len(g[v])
    ```

    > 인용문은 왼쪽 선과 함께 들여 쓴다.
    > 두 번째 줄.

    ---

    ### 더 볼 것

    [[해밀턴 경로]]와 비교한다. ^compare


    ## 모르는 것


    """

    // MARK: Pages

    static let width: CGFloat = 800
    /// Blocks drawn as a widget that the caret swaps for their source, of whatever height that is.
    static let swaps: Set<String> = ["BlockMath", "Table", "FencedCode"]
    /// note.css's --body × --leading.
    static let line = 16 * 1.78

    static func webView(script: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: probe, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        return WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 3000), configuration: config)
    }

    static func load(_ view: WKWebView, _ html: String, until ready: String) async throws {
        view.loadHTMLString(html, baseURL: nil)
        for _ in 0..<200 {
            // A call that lands on the blank page before the note's commits is dropped with an error; it's asked again.
            if (try? await view.callAsyncJavaScript("return \(ready)", contentWorld: .page)) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        // A font that never settles leaves `fonts.ready` pending, and WebKit drops a call whose promise is collected.
        _ = try await view.callAsyncJavaScript("await Promise.race([document.fonts.ready, new Promise(r => setTimeout(r, 2000))]); return true",
                                               contentWorld: .page)
    }

    static func reader(_ text: String) async throws -> WKWebView {
        let view = webView(script: NoteStyle.reader)
        let html = HTMLView(body: HTMLRenderer.render(ParsedNote(text))).page(accent: CourseAccent.presets[0].accent)
        try await load(view, html, until: "document.readyState === 'complete' && !!document.body?.classList.contains('note')")
        // Folded callouts are the reader's alone (docs/SPEC.md); their insides are compared open.
        _ = try await view.callAsyncJavaScript("document.querySelectorAll('details').forEach(d => d.open = true); return true", contentWorld: .page)
        return view
    }

    static func editor(_ text: String) async throws -> WKWebView {
        let view = webView(script: NoteStyle.editor)
        let html = MarkdownEditor(text: .constant(""), math: .latex, live: true, insert: .constant(nil), saveFile: { _, _ in nil }, openNote: { _ in })
            .page(accent: CourseAccent.presets[0].accent)
        try await load(view, html, until: "typeof cb !== 'undefined'")
        _ = try await view.callAsyncJavaScript("cb.load({ text, syntax: 'latex', live: true }); return true", arguments: ["text": text], contentWorld: .page)
        return view
    }

    // MARK: Checks

    /// Every visible character's place, lined up between the two pages by text. A line whose offset differs from the
    /// line before it is where the editor drifts from the reader.
    @Test func unfocusedEditorMatchesTheReader() async throws {
        let readerView = try await Self.reader(Self.sample), editorView = try await Self.editor(Self.sample)
        let reader = try await Self.glyphs(readerView, root: "document.body")
        let editor = try await Self.glyphs(editorView, root: "document.querySelector('.cm-content')")
        defer { withExtendedLifetime((readerView, editorView)) {} }
        var problems: [String] = []
        var drift = (dx: 0.0, dy: 0.0), lastTop = -1.0
        for (r, e) in Self.align(reader, editor) {
            guard !r.math, abs(r.top - lastTop) > 1 else { continue }
            lastTop = r.top
            let d = (dx: e.left - r.left, dy: e.top - r.top)
            if abs(d.dy - drift.dy) > 1 || abs(d.dx - drift.dx) > 1.5 {
                problems.append(String(format: "“%@”: editor %+.1f, %+.1f px from the reader (line before %+.1f, %+.1f)", r.context, d.dx, d.dy, drift.dx, drift.dy))
            }
            drift = d
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// Clicking into a line reveals its markup, but no other block moves: blocks above never, blocks below only when
    /// the caret's block trades its rendering for source of another height (math, tables, code, quotes).
    @Test func theCaretMovesNoOtherBlock() async throws {
        let view = try await Self.editor(Self.sample)
        let lines = try await Self.js(view, "return cb.debug.view.state.doc.lines") as! Int
        let base = try await Self.js(view, "return probe.lineTops()") as! [Double]
        var problems: [String] = []
        for n in 1...lines {
            let result = try await Self.js(view, "probe.caretAt(n); const t = probe.lineTops(); probe.blur(); return [t, probe.block(n), /^[\\s>]*$/.test(cb.debug.view.state.doc.line(n).text)]", ["n": n]) as! [Any]
            let tops = result[0] as! [Double], block = result[1] as! [Any]
            let (first, last, kind, blank) = (block[0] as! Int, block[1] as! Int, block[2] as! String, result[2] as! Bool)
            let swaps = Self.swaps.contains(kind)
            for m in 1...lines where m < first || (m > last && !swaps) {
                let moved = tops[m - 1] - base[m - 1]
                // A gap thinner than a line opens by up to a line so the caret has one; never more, never upward.
                let room = blank && m > last ? Self.line : 0
                if moved > room + 0.5 || moved < -0.5 {
                    problems.append(String(format: "caret on line %d (%@): line %d moved %+.1f px", n, kind, m, moved))
                    break
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// What's typed lands where the caret was drawn.
    @Test func typingLandsOnTheCaret() async throws {
        let view = try await Self.editor(Self.sample)
        let lines = try await Self.js(view, "return cb.debug.view.state.doc.lines") as! Int
        var problems: [String] = []
        for n in 1...lines {
            let r = try await Self.js(view, "return probe.typeAt(n)", ["n": n]) as! [Any]
            // A line typed under a table is a row of it (GFM), and the caret in a table shows its source; `---x` is no rule.
            if Self.swaps.contains(r[2] as! String) || r[2] as! String == "Paragraph" && r[3] as! String == "HorizontalRule" { continue }
            let (before, after) = (r[0] as! Double, r[1] as! Double)
            if abs(after - before) > 1.5 { problems.append(String(format: "line %d: caret at %.1f, typed text at %.1f (%+.1f px)", n, before, after, after - before)) }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    // MARK: Helpers

    /// `math`: KaTeX sets each glyph on its own baseline, so math never marks where a line starts.
    struct Glyph { var char: String, top: Double, left: Double, math: Bool, context: String }

    static func js(_ view: WKWebView, _ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await view.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)
    }

    static func glyphs(_ view: WKWebView, root: String) async throws -> [Glyph] {
        let raw = try await js(view, "return probe.glyphs(\(root))") as! [[Any]]
        let chars = raw.map { $0[0] as! String }
        return raw.enumerated().map { i, g in
            Glyph(char: chars[i], top: g[1] as! Double, left: g[2] as! Double, math: g[3] as! Int == 1, context: chars[i..<min(i + 16, chars.count)].joined())
        }
    }

    /// Pairs equal characters in order, skipping text only one page shows (list numbers, a code block's language).
    static func align(_ a: [Glyph], _ b: [Glyph]) -> [(Glyph, Glyph)] {
        var pairs: [(Glyph, Glyph)] = [], i = 0, j = 0
        func same(_ i: Int, _ j: Int, _ k: Int) -> Bool {
            (0..<k).allSatisfy { i + $0 < a.count && j + $0 < b.count && a[i + $0].char == b[j + $0].char }
        }
        while i < a.count && j < b.count {
            if a[i].char == b[j].char { pairs.append((a[i], b[j])); i += 1; j += 1; continue }
            if let k = (1...40).first(where: { same(i, j + $0, 6) }) { j += k } else if let k = (1...40).first(where: { same(i + $0, j, 6) }) { i += k } else { i += 1; j += 1 }
        }
        return pairs
    }

    static let probe = """
    window.probe = {
      // KaTeX's MathML copy is there for screen readers, clipped to nothing.
      glyphs(root) {
        const out = [], range = document.createRange(), walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let n = walk.nextNode(); n; n = walk.nextNode()) {
          if (n.parentElement.closest('.katex-mathml')) continue;
          for (let i = 0; i < n.data.length; i++) {
            if (/\\s/.test(n.data[i])) continue;
            range.setStart(n, i); range.setEnd(n, i + 1);
            const r = range.getBoundingClientRect();
            if (r.height) out.push([n.data[i], r.top + scrollY, r.left, n.parentElement.closest('.katex') ? 1 : 0]);
          }
        }
        return out;
      },
      lineTops() {
        const v = cb.debug.view, d = v.state.doc, out = [];
        for (let n = 1; n <= d.lines; n++) { const c = v.coordsAtPos(d.line(n).from, 1); out.push(c ? c.top + scrollY : -1); }
        return out;
      },
      // The top-level block holding line n as [first, last, name]; blank lines between blocks are a run of their own.
      block(n) {
        const d = cb.debug.view.state.doc;
        for (let c = cb.debug.tree().topNode.firstChild; c; c = c.nextSibling) {
          const a = d.lineAt(c.from).number, b = d.lineAt(c.to).number;
          if (a <= n && n <= b) return [a, b, c.name];
        }
        let a = n, b = n;
        while (a > 1 && !d.line(a - 1).text.trim()) a--;
        while (b < d.lines && !d.line(b + 1).text.trim()) b++;
        return [a, b, "Blank"];
      },
      caretAt(n) { const v = cb.debug.view; v.dispatch({ selection: { anchor: v.state.doc.line(n).to } }); cb.debug.focus(true); },
      blur() { cb.debug.focus(false); },
      middle(pos, side) { const c = cb.debug.view.coordsAtPos(pos, side); return c ? (c.top + c.bottom) / 2 + scrollY : -1; },
      // Middles, not tops: an empty line's caret is the line's height and a letter only its font's.
      typeAt(n) {
        const v = cb.debug.view;
        probe.caretAt(n);
        const at = v.state.selection.main.head, before = probe.middle(at, -1), was = probe.block(n)[2];
        v.dispatch({ changes: { from: at, insert: "x" }, selection: { anchor: at + 1 } });
        const after = probe.middle(at + 1, -1), kind = probe.block(v.state.doc.lineAt(at).number)[2];
        v.dispatch({ changes: { from: at, to: at + 1 } });
        probe.blur();
        return [before, after, kind, was];
      },
    };
    """
}
