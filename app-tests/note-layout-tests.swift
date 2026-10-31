import FolioDomain
import Foundation
import Testing
import WebKit
@testable import Folio

/// The editor laid out by WebKit, as in the app. It draws the source with its markup dimmed, never hidden, so the caret
/// moves nothing. Each failure names the line and how far it moved, so a fix can start from the report.
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

    static func editor(_ text: String) async throws -> WKWebView {
        let view = webView(script: NoteStyle.editor)
        let html = MarkdownEditor(text: .constant(""), math: .latex, insert: .constant(nil), saveFile: { _, _ in nil }, openNote: { _ in })
            .page(accent: CourseAccent.presets[0].accent)
        try await load(view, html, until: "typeof cb !== 'undefined'")
        _ = try await view.callAsyncJavaScript("cb.load({ text, syntax: 'latex' }); return true", arguments: ["text": text], contentWorld: .page)
        return view
    }

    // MARK: Checks

    @Test func theCaretMovesNothing() async throws {
        let view = try await Self.editor(Self.sample)
        let lines = try await Self.js(view, "return cb.debug.view.state.doc.lines") as! Int
        let base = try await Self.js(view, "return probe.lineTops()") as! [Double]
        var problems: [String] = []
        for n in 1...lines {
            let result = try await Self.js(view, "probe.caretAt(n); const t = probe.lineTops(); probe.blur(); return [t, probe.block(n)]", ["n": n]) as! [Any]
            let tops = result[0] as! [Double], kind = (result[1] as! [Any])[2] as! String
            for m in 1...lines {
                let moved = tops[m - 1] - base[m - 1]
                if abs(moved) > 0.5 {
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
            // What's typed can make the line another block, drawn in another font or box: a line under a table is a row
            // of it (GFM), `| --- |x` ends the table and `---x` the rule, and text right under a quote joins it
            // (CommonMark's lazy continuation), as in Obsidian.
            let (now, was) = (r[2] as! String, r[3] as! String)
            if now != was && (now == "Table" || was == "Table" || was == "HorizontalRule" || now == "Blockquote") { continue }
            let (before, after) = (r[0] as! Double, r[1] as! Double)
            if abs(after - before) > 1.5 { problems.append(String(format: "line %d: caret at %.1f, typed text at %.1f (%+.1f px)", n, before, after, after - before)) }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test func arrowsMoveNothing() async throws {
        let view = try await Self.editor(Self.sample)
        let base = try await Self.js(view, "return probe.lineTops()") as! [Double]
        let walk = try await Self.js(view, """
            const v = cb.debug.view, out = [];
            probe.caretAt(1); v.dispatch({ selection: { anchor: 0 } });
            for (let i = 0; i < 200; i++) {
              const n = v.state.doc.lineAt(v.state.selection.main.head).number;
              out.push([n, probe.block(n), probe.lineTops()]);
              const at = v.state.selection.main.head;
              probe.key("ArrowDown");
              if (v.state.selection.main.head === at) break;
            }
            probe.blur();
            return out;
            """) as! [[Any]]
        let lines = base.count
        var problems: [String] = []
        for step in walk {
            let n = step[0] as! Int, kind = (step[1] as! [Any])[2] as! String, tops = step[2] as! [Double]
            for m in 1...lines {
                let moved = tops[m - 1] - base[m - 1]
                if abs(moved) > 0.5 {
                    problems.append(String(format: "caret on line %d (%@): line %d moved %+.1f px", n, kind, m, moved))
                    break
                }
            }
        }
        #expect(walk.last?.first as? Int == lines, "the walk stopped at line \(walk.last?.first ?? 0) of \(lines)")
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// The caret walks the raw text: no mark is hung, hidden or padded, so every line starts at the same x.
    @Test func everyLineStartsInOneColumn() async throws {
        let view = try await Self.editor(Self.sample)
        let starts = try await Self.js(view, """
            const v = cb.debug.view, d = v.state.doc, out = [];
            for (let n = 1; n <= d.lines; n++) out.push(v.coordsAtPos(d.line(n).from, 1).left);
            return out;
            """) as! [Double]
        let off = starts.enumerated().filter { abs($0.element - starts[0]) > 0.5 }.map { String(format: "line %d starts at %+.1f px", $0.offset + 1, $0.element - starts[0]) }
        #expect(off.isEmpty, "\(off.joined(separator: "\n"))")
    }

    /// A heading's `#`s and a list item's marker stay where they are drawn whether or not the caret is on the line.
    @Test func markupMovesNoText() async throws {
        let view = try await Self.editor(Self.sample)
        let shifts = try await Self.js(view, """
            const v = cb.debug.view, d = v.state.doc, out = [];
            const start = (n) => { const m = /^\\s*(?:#{1,6} |(?:[-*+]|\\d+[.)]) (?:\\[[ xX]\\] )?)/.exec(d.line(n).text); return m && d.line(n).length > m[0].length ? d.line(n).from + m[0].length : null; };
            for (let n = 1; n <= d.lines; n++) {
              const at = start(n); if (at === null) continue;
              probe.blur(); const before = v.coordsAtPos(at, 1).left;
              probe.caretAt(n); const after = v.coordsAtPos(at, 1).left; probe.blur();
              if (Math.abs(after - before) > 0.5) out.push(`line ${n}: text moved ${(after - before).toFixed(1)} px`);
            }
            return out;
            """) as! [String]
        #expect(shifts.isEmpty, "\(shifts.joined(separator: "\n"))")
    }

    /// Enter on an empty item steps out a level, then out of the list; on an empty `>` line, out of the quote.
    @Test func enterOnAnEmptyMarkerEndsTheBlock() async throws {
        let view = try await Self.editor("- a\n    - b\n\n> q")
        let text = try await Self.js(view, """
            const v = cb.debug.view;
            probe.caretAt(2); for (let i = 0; i < 3; i++) probe.key("Enter");
            probe.caretAt(v.state.doc.lines); for (let i = 0; i < 2; i++) probe.key("Enter");
            return v.state.doc.toString();
            """) as! String
        #expect(text == "- a\n    - b\n\n\n\n> q\n\n")
    }

    /// Inline math stays source; the caret inside it floats the rendered formula over the text.
    @Test func caretInMathShowsItRendered() async throws {
        let view = try await Self.editor("a $x^2$ b")
        let tips = try await Self.js(view, """
            const v = cb.debug.view, tip = () => !!document.querySelector(".cm-math-tip .katex");
            probe.caretAt(1); const outside = tip();
            v.dispatch({ selection: { anchor: 4 } }); const inside = tip();
            probe.blur(); return [outside, inside, tip()];
            """) as! [Bool]
        #expect(tips == [false, true, false])
    }

    // MARK: Helpers

    static func js(_ view: WKWebView, _ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await view.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)
    }

    static let probe = """
    window.probe = {
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
      key(k) { cb.debug.view.contentDOM.dispatchEvent(new KeyboardEvent("keydown", { key: k, code: k, bubbles: true, cancelable: true })); },
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
