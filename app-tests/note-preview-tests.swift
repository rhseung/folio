import AppKit
import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing
import WebKit
@testable import Folio

/// A note preview's page in a window that's never shown, with the note it shows, written back on a tick as the note
/// screen does.
@MainActor final class PreviewRig {
    let page: NotePreviewPage
    let window: NSWindow
    var text: String
    var baseURL: URL?
    var math: MathSyntax
    var accent = CourseAccent.presets[0].accent
    /// Stands for the workspace's `notesRevision`, which another note's change bumps.
    var revision = 0

    init(_ text: String, baseURL: URL? = nil, editable: Bool = false, height: CGFloat = 600, embeds: NoteEmbedSource? = nil,
         math: MathSyntax = .latex) {
        page = NotePreviewPage.take()
        page.embeds = embeds
        window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 900, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        page.view.frame = window.contentView!.bounds
        page.view.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(page.view)
        Self.keepDrawing(page.view, in: window)
        self.text = text
        self.baseURL = baseURL
        self.math = math
        if editable {
            page.edit = { [unowned self] from, to, old, new in
                var lines = self.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard from >= 1, to <= lines.count, lines[(from - 1)..<to].joined(separator: "\n") == old else { return false }
                lines.replaceSubrange((from - 1)..<to, with: [new])
                self.show(lines.joined(separator: "\n"))
                return true
            }
        }
        show(text)
    }

    /// WebKit stops a page's rendering updates while its window isn't on screen, and a widget's frame then never
    /// hears it was resized. The window is put in the window list far off every screen, and WebKit told not to
    /// judge by what covers it, so it draws as in the app; nothing shows and nothing takes focus.
    static func keepDrawing(_ view: WKWebView, in window: NSWindow) {
        let setter = Selector(("_setWindowOcclusionDetectionEnabled:"))
        if view.responds(to: setter), let method = class_getInstanceMethod(type(of: view), setter) {
            typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Set.self)(view, setter, false)
        }
        window.orderBack(nil)
    }

    func show(_ text: String) {
        self.text = text
        page.show(text, baseURL: baseURL, math: math, accent: accent, dark: false, revision: revision)
    }

    func close() {
        window.orderOut(nil)
        page.view.removeFromSuperview()
        page.recycle()
    }

    /// Until the page shows the note with every widget's height known, or a few seconds pass.
    func settle() async {
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            if page.settled { break }
        }
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// `body` run as a function in the note's page.
    func js(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await page.view.callAsyncJavaScript(body, arguments: arguments, contentWorld: .defaultClient)
    }

    func number(_ body: String) async throws -> Double? { try await js(body) as? Double }
}

/// The preview: the note's blocks in a web view, kept as they are while the note changes around them.
@MainActor @Suite(.serialized, .timeLimit(.minutes(2)))
struct NotePreviewTests {
    @Test func showsTheNoteWithItsSourceLines() async throws {
        let rig = PreviewRig("---\ntitle: x\n---\n# Title\n\nFirst paragraph\n\n- one\n- two")
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('h1')?.textContent") as? String == "Title")
        // Lines count from the top of the file, frontmatter included, as the editor counts them.
        let lines = try #require(try await rig.js("return [...document.body.children].map(n => Number(n.dataset.line))") as? [Double])
        #expect(lines == [4, 6, 8])
    }

    /// Typing in the editor makes only the changed block again, so what's around it (a running widget) stays.
    @Test func keepsTheBlocksThatDidNotChange() async throws {
        let rig = PreviewRig("# Title\n\nFirst\n\nSecond")
        defer { rig.close() }
        await rig.settle()
        _ = try await rig.js("document.querySelector('h1').dataset.mark = 'kept'")
        rig.show("Intro\n\n# Title\n\nFirst, changed\n\nSecond")
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('h1').dataset.mark") as? String == "kept")
        #expect(try await rig.js("return document.querySelector('h1').dataset.line") as? String == "3")
        #expect(try await rig.js("return document.body.textContent.includes('First, changed')") as? Bool == true)
    }

    @Test func tickingABoxWritesItToTheNote() async throws {
        let rig = PreviewRig("# Tasks\n\n- [ ] one\n- [x] two\n> - [ ] quoted", editable: true)
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelectorAll('input[type=checkbox]:not([disabled])').length") as? Int == 2)
        _ = try await rig.js("document.querySelector('input[data-line=\"3\"]').click()")
        await rig.settle()
        #expect(rig.text == "# Tasks\n\n- [x] one\n- [x] two\n> - [ ] quoted")
        #expect(try await rig.js("return document.querySelector('input[data-line=\"3\"]').checked") as? Bool == true)
        _ = try await rig.js("document.querySelector('input[data-line=\"4\"]').click()")
        await rig.settle()
        #expect(rig.text == "# Tasks\n\n- [x] one\n- [ ] two\n> - [ ] quoted")
        // swift-markdown reads no box in a quoted list, but the line is still a task to tick.
        #expect(rig.page.tick(line: 5))
        #expect(rig.text.hasSuffix("> - [x] quoted"))
        // A line that's no longer a task changes nothing.
        #expect(!rig.page.tick(line: 1))
    }

    /// A box carries its line in the body; the note's frontmatter is above it.
    @Test func aBoxBelowFrontmatterTicksItsOwnLine() async throws {
        let rig = PreviewRig("---\ntitle: x\n---\n- [ ] one\n- [ ] two", editable: true)
        defer { rig.close() }
        await rig.settle()
        _ = try await rig.js("document.querySelectorAll('input[type=checkbox]')[1].click()")
        await rig.settle()
        #expect(rig.text == "---\ntitle: x\n---\n- [ ] one\n- [x] two")
    }

    /// With no way to write the note back, a box shows its state and doesn't change it.
    @Test func boxesStayWithoutAWayToWrite() async throws {
        let rig = PreviewRig("- [ ] one")
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('input[type=checkbox]').disabled") as? Bool == true)
        _ = try await rig.js("document.querySelector('input[type=checkbox]').click()")
        await rig.settle()
        #expect(rig.text == "- [ ] one")
        #expect(try await rig.js("return document.querySelector('input[type=checkbox]').checked") as? Bool == false)
    }

    /// A callout folded or opened stays so when the note is shown again, even when its block is made again.
    @Test func aFoldOutlivesTheBlock() async throws {
        let rig = PreviewRig("> [!theorem]- Main\n> Body\n\nAfter")
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('details.callout').open") as? Bool == false)
        _ = try await rig.js("document.querySelector('details.callout > summary').click()")
        try await Task.sleep(for: .milliseconds(100))
        rig.show("> [!theorem]- Main\n> Body, changed\n\nAfter")
        await rig.settle()
        #expect(try await rig.js("return document.body.textContent.includes('Body, changed')") as? Bool == true)
        #expect(try await rig.js("return document.querySelector('details.callout').open") as? Bool == true)
    }

    /// Beside the editor the preview puts the editor's top line at the top of the page, below the margin.
    @Test func followsTheEditorsTopLine() async throws {
        let text = (1...80).map { "Paragraph \($0)" }.joined(separator: "\n\n")
        let rig = PreviewRig(text)
        defer { rig.close() }
        await rig.settle()
        let line = 2 * 40 - 1
        rig.page.follow(line: line, frac: 0)
        await rig.settle()
        let top = try #require(try await rig.number("return document.querySelector('[data-line=\"\(line)\"]').getBoundingClientRect().top"))
        #expect(abs(top - NoteLook.margin) <= 1, "\(top)")
        rig.page.follow(line: 1, frac: 0)
        await rig.settle()
        #expect(try await rig.number("return scrollY") == 0)
    }

    /// The page goes on past the note's end, so the editor's last line can be followed to the top.
    @Test func thePageScrollsPastItsEnd() async throws {
        let rig = PreviewRig((1...40).map { "Paragraph \($0)" }.joined(separator: "\n\n"))
        defer { rig.close() }
        await rig.settle()
        _ = try await rig.js("scrollTo(0, 1e6)")
        let bottom = try #require(try await rig.number("return document.body.lastElementChild.getBoundingClientRect().bottom"))
        #expect(bottom < 120, "\(bottom)")
    }

    /// Blocks wider than the column scroll sideways inside it; the page itself never does.
    @Test func wideBlocksScrollInsideTheColumn() async throws {
        let wide = String(repeating: "x", count: 400)
        let rig = PreviewRig("```\n\(wide)\n```\n\n$$\n\\sum \(String(repeating: "a + ", count: 120)) b\n$$\n\n| a |\n|---|\n| \(wide) |")
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.number("return document.documentElement.scrollWidth - document.documentElement.clientWidth") == 0)
        let right = try #require(try await rig.number("return Math.max(...[...document.body.children].map(n => n.getBoundingClientRect().right))"))
        let column = (900 - NoteLook.measure) / 2 + NoteLook.measure - NoteLook.margin
        #expect(right <= column + 1, "\(right) past \(column)")
    }

    /// `%`, `#` and `&` in a formula's text are the characters, not TeX's comment and markup.
    @Test func textInMathReadsAsWritten() async throws {
        let rig = PreviewRig("$\\textbf{오차 5% 이내} \\text{과제 #3 \\& 4} \\textit{A & B}$")
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelectorAll('.math-error').length") as? Int == 0)
        #expect(try await rig.js("return document.querySelectorAll('.katex').length") as? Int == 1)
    }

    /// AsciiMath's quoted text lands in `\text{…}` as written, so its `#` is the character there too, as the edit view
    /// shows it.
    @Test func asciiMathTextReadsAsWritten() async throws {
        let rig = PreviewRig(##"$min{|F|: G - F " separates " x, y} = max{"# edge-disjoint " x,y- "paths"}$"##, math: .asciimath)
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelectorAll('.math-error').length") as? Int == 0)
        #expect(try await rig.js("return document.querySelectorAll('.katex').length") as? Int == 1)
    }

    /// A bar closes the bar opened before it in the same brackets; asciimath2tex alone paired `|X| >= |I|` as one
    /// `\left| X | >= \right|` and read `|:` in `|F|:` as a bracket that ate the colon. Read from the TeX KaTeX keeps
    /// beside what it drew, which is what the edit view's bubble draws too (`NoteMath`).
    @Test func asciiMathBarsPairInOrder() async throws {
        let cases: [(String, String)] = [
            (#"|(bigcup_(i in I) A_i) cap (bigcup_(i in J) B_i)| >= |I| + |J| - m"#,
             #"\left \lvert \left ( \bigcup_{i \in I} A_{i} \right ) \cap \left ( \bigcup_{i \in J} B_{i} \right ) \right \rvert \ge \left \lvert I \right \rvert + \left \lvert J \right \rvert - m"#),
            (#"|det(A)| = |lambda_1| |lambda_2|"#,
             #"\left \lvert \det{\left ( A \right )} \right \rvert = \left \lvert \lambda_{1} \right \rvert \left \lvert \lambda_{2} \right \rvert"#),
            (#"min{|F|: G}"#, #"\min \left \lbrace \left \lvert F \right \rvert : G \right \rbrace"#),
            (#"||x|| + |y|"#, #"\left \lvert \left \lvert x \right \rvert \right \rvert + \left \lvert y \right \rvert"#),
            // As before: a norm, explicit bars, a lone bar and AsciiMath's tokens with a bar in them.
            (#"||x||"#, #"\left \lvert \left \lvert x \right \rvert \right \rvert"#),
            (#"|:x:|"#, #"\left \lvert x \right \rvert"#),
            (#"a|b"#, "a | b"),
            (#"{x | x > 0}"#, #"\left \lbrace x \mid x > 0 \right \rbrace"#),
            (#"x |-> y"#, #"x \mapsto y"#),
            (#""a|b" + |x|"#, #"\text{a|b} + \left \lvert x \right \rvert"#),
        ]
        let rig = PreviewRig(cases.map { "$\($0.0)$" }.joined(separator: "\n\n"), math: .asciimath)
        defer { rig.close() }
        await rig.settle()
        let read = try await rig.js("return [...document.querySelectorAll('.math')].map(m => m.querySelector('annotation')?.textContent ?? '')") as? [String]
        #expect(read == cases.map(\.1))
    }

    /// The page loads the note's own pictures and nothing from outside.
    @Test func picturesComeFromTheNotesFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "assets"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: NoteRender.fixtures.appending(path: "assets/sample.png"), to: folder.appending(path: "assets/sample.png"))
        let rig = PreviewRig("![](assets/sample.png)\n\n![](https://example.com/x.png)", baseURL: folder)
        defer { rig.close() }
        await rig.settle()
        for _ in 0..<40 where try await rig.number("return document.images[0].naturalWidth") ?? 0 == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try await rig.number("return document.images[0].naturalWidth") ?? 0 > 0)
        #expect(try await rig.number("return document.images[1].naturalWidth") == 0)
    }

    /// A picture or diagram pressed in the preview opens large over the note and closes by Esc, its button or a press
    /// beside it; one inside a link opens the link instead (#378).
    @Test func aPictureOpensLargeAndCloses() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "assets"), withIntermediateDirectories: true)
        for name in ["wide-proof.svg", "sample.png"] {
            try FileManager.default.copyItem(at: NoteRender.fixtures.appending(path: "assets/\(name)"), to: folder.appending(path: "assets/\(name)"))
        }
        let exam = UUID()
        let rig = PreviewRig("![](assets/wide-proof.svg)\n\n```mermaid\ngraph LR\nA-->B\n```\n\n[![](assets/sample.png)](folio://exam/\(exam))", baseURL: folder)
        defer { rig.close() }
        var opened: [AppLink] = []
        rig.page.openLink = OpenLinkAction { link, _, _ in opened.append(link) }
        await rig.settle()
        for _ in 0..<40 where try await rig.number("return Math.min(...[...document.images].map(i => i.naturalWidth))") ?? 0 == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        let open = "return document.querySelector('.figure-viewer') != null"
        let sheet = "return document.querySelector('.figure-sheet').getBoundingClientRect().width"
        let key = "document.body.dispatchEvent(new KeyboardEvent('keydown', {key, metaKey: command, bubbles: true}))"
        let column = try #require(try await rig.number("return document.images[0].getBoundingClientRect().width"))

        _ = try await rig.js("document.images[0].click()")
        #expect(try await rig.js(open) as? Bool == true)
        // Drawn larger than the column holds it; the linked picture isn't one of those to step through.
        let fitted = try #require(try await rig.number(sheet))
        #expect(fitted > column)
        #expect(try await rig.js("return document.querySelector('.figure-count').textContent") as? String == "1 / 2")
        _ = try await rig.js(key, ["key": "=", "command": true])
        #expect(try await rig.number(sheet) ?? 0 > fitted)
        _ = try await rig.js(key, ["key": "0", "command": true])
        #expect(try await rig.number(sheet) == fitted)
        // Pressed twice: its own size, and back.
        let tap = "const el = document.querySelector('.figure-sheet > *'), r = el.getBoundingClientRect();"
            + "for (const type of ['pointerdown', 'pointerup']) el.dispatchEvent(new PointerEvent(type, {pointerId: 1, isPrimary: true,"
            + " clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, bubbles: true}))"
        _ = try await rig.js(tap)
        _ = try await rig.js(tap)
        #expect(try await rig.js("return document.querySelector('.figure-actual').textContent") as? String == "100%")
        _ = try await rig.js(tap)
        _ = try await rig.js(tap)
        #expect(try await rig.number(sheet) == fitted)
        // A touch pinch from the fitted picture keeps its zoom when the fingers lift, apart as they are.
        let pinch = "const el = document.querySelector('.figure-sheet > *'), r = el.getBoundingClientRect(), y = r.top + r.height / 2, x = r.left + r.width / 2;"
            + "const send = (type, id, at) => el.dispatchEvent(new PointerEvent(type, {pointerId: id, pointerType: 'touch', clientX: at, clientY: y, bubbles: true}));"
            + "send('pointerdown', 1, x - 40); send('pointerdown', 2, x + 40); send('pointermove', 2, x + 240); send('pointerup', 1, x - 40); send('pointerup', 2, x + 240)"
        _ = try await rig.js(pinch)
        #expect(try await rig.number(sheet) ?? 0 > fitted)
        #expect(try await rig.js("return document.querySelector('.figure-count').textContent") as? String == "1 / 2")
        _ = try await rig.js(key, ["key": "0", "command": true])
        // The next is the diagram, drawn again from its own SVG.
        _ = try await rig.js(key, ["key": "ArrowRight", "command": false])
        #expect(try await rig.js("return document.querySelector('.figure-sheet > svg') != null") as? Bool == true)
        _ = try await rig.js(key, ["key": "Escape", "command": false])
        #expect(try await rig.js(open) as? Bool == false)

        _ = try await rig.js("document.querySelector('figure.mermaid').click()")
        #expect(try await rig.js("return document.querySelector('.figure-count').textContent") as? String == "2 / 2")
        _ = try await rig.js("document.querySelector('.figure-close').click()")
        #expect(try await rig.js(open) as? Bool == false)

        _ = try await rig.js("document.images[0].click()")
        let beside = "const v = document.querySelector('.figure-viewer');"
            + "for (const type of ['pointerdown', 'pointerup']) v.dispatchEvent(new PointerEvent(type, {pointerId: 1, isPrimary: true, clientX: 4, clientY: 300, bubbles: true}))"
        _ = try await rig.js(beside)
        #expect(try await rig.js(open) as? Bool == false)

        _ = try await rig.js("document.querySelector('a img').click()")
        for _ in 0..<40 where opened.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(try await rig.js(open) as? Bool == false)
        #expect(opened == [AppLink(.exam, exam)])
    }

    /// A page handed to another note keeps nothing of the last one.
    /// A link into the app opens through the window's one opener, whether a wiki link or a markdown link.
    @Test func aClickOnALinkIntoTheAppOpensIt() async throws {
        let material = UUID()
        let exam = UUID()
        let rig = PreviewRig("See [[material:\(material)#page=12|slides]] and [the exam](folio://exam/\(exam)).")
        defer { rig.close() }
        var opened: [AppLink] = []
        rig.page.openLink = OpenLinkAction { link, _, _ in opened.append(link) }
        await rig.settle()
        _ = try await rig.js("document.querySelector('a.wikilink').click()")
        for _ in 0..<40 where opened.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        _ = try await rig.js("document.querySelectorAll('a')[1].click()")
        for _ in 0..<40 where opened.count < 2 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(opened == [AppLink(.material, material, anchor: .page(12)), AppLink(.exam, exam)])
    }

    /// A copied address between brackets or on its own opens as a link into the app (#347).
    @Test func aClickOnACopiedAddressOpensIt() async throws {
        let material = UUID()
        let exam = UUID()
        let rig = PreviewRig("See [[folio://material/\(material)#page=2]] and folio://exam/\(exam).")
        defer { rig.close() }
        var opened: [AppLink] = []
        rig.page.openLink = OpenLinkAction { link, _, _ in opened.append(link) }
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('a.wikilink.missing') == null && document.querySelectorAll('a[href^=\"folio://\"]').length == 2") as? Bool == true)
        _ = try await rig.js("document.querySelector('a.wikilink').click()")
        for _ in 0..<40 where opened.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        _ = try await rig.js("document.querySelectorAll('a')[1].click()")
        for _ in 0..<40 where opened.count < 2 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(opened == [AppLink(.material, material, anchor: .page(2)), AppLink(.exam, exam)])
    }

    /// The page's menu is told what it was opened on: the link, and the heading or block under the pointer.
    @Test func theMenuKnowsTheLinkAndHeadingUnderThePointer() async throws {
        let rig = PreviewRig("# Matchings\n\nA [link](folio://course/\(graphTheory)).\n\nKept ^proof")
        defer { rig.close() }
        await rig.settle()
        func menu(on selector: String) async throws {
            _ = try await rig.js("document.querySelector(s).dispatchEvent(new MouseEvent('contextmenu', {bubbles: true}))", ["s": selector])
            try? await Task.sleep(for: .milliseconds(150))
        }
        try await menu(on: "h1")
        #expect(rig.page.menuAnchor == .heading("Matchings") && rig.page.menuHref == nil)
        try await menu(on: "a")
        #expect(rig.page.menuHref == "folio://course/\(graphTheory)")
        try await menu(on: "[id='^proof']")
        #expect(rig.page.menuAnchor == .block("proof"))
    }

    /// The selection says where it starts: on a touch screen a long press selects, and the edit menu links to that
    /// heading or block.
    @Test func theSelectionKnowsItsHeadingAndBlock() async throws {
        let rig = PreviewRig("# Matchings\n\nKept ^proof\n\nPlain")
        defer { rig.close() }
        await rig.settle()
        func select(_ selector: String) async throws {
            _ = try await rig.js("getSelection().selectAllChildren([...document.querySelectorAll(s)].at(-1))", ["s": selector])
            try? await Task.sleep(for: .milliseconds(150))
        }
        try await select("h1")
        #expect(rig.page.selectionAnchor == .heading("Matchings"))
        try await select("[id='^proof']")
        #expect(rig.page.selectionAnchor == .block("proof"))
        try await select("p")
        #expect(rig.page.selectionAnchor == nil)
    }

    /// Opened at a heading, the page shows the heading at its top.
    @Test func aLinkToAHeadingScrollsToIt() async throws {
        let filler = (1...60).map { "Paragraph \($0)" }.joined(separator: "\n\n")
        let rig = PreviewRig("# Top\n\n\(filler)\n\n## Far down\n\nEnd")
        defer { rig.close() }
        await rig.settle()
        rig.page.reveal(.heading("Far down"))
        try? await Task.sleep(for: .milliseconds(300))
        let top = try #require(try await rig.number("return document.getElementById('far-down').getBoundingClientRect().top"))
        #expect(abs(top) < 80)
    }

    /// A footnote's number goes down to the note's list, and the list's arrow back up to where it was referenced.
    @Test func footnotesLinkToTheListAndBack() async throws {
        let filler = (1...60).map { "Paragraph \($0)" }.joined(separator: "\n\n")
        let rig = PreviewRig("Claim[^src].\n\n\(filler)\n\n[^src]: Where it comes from")
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('section.footnotes li')?.textContent") as? String == "Where it comes from ↩\u{FE0E}")
        func top(_ id: String) async throws -> Double {
            try #require(try await rig.js("return document.getElementById(id).getBoundingClientRect().top", ["id": id]) as? Double)
        }
        _ = try await rig.js("document.querySelector('sup.footnote-ref a').click()")
        for _ in 0..<40 { if abs(try await top("fn-1")) < 80 { break }; try? await Task.sleep(for: .milliseconds(50)) }
        #expect(abs(try await top("fn-1")) < 80)
        _ = try await rig.js("document.querySelector('a.footnote-back').click()")
        for _ in 0..<40 { if abs(try await top("fnref-1")) < 80 { break }; try? await Task.sleep(for: .milliseconds(50)) }
        #expect(abs(try await top("fnref-1")) < 80)
    }

    @Test func aRecycledPageStartsEmpty() async throws {
        let rig = PreviewRig("# One")
        await rig.settle()
        let page = rig.page
        rig.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await page.view.callAsyncJavaScript("return document.body.children.length", contentWorld: .defaultClient) as? Int == 0)
    }
}

/// Embeds and block references draw the other notes of the course, found by title.
@MainActor @Suite(.serialized, .timeLimit(.minutes(2)))
struct NoteEmbedPreviewTests {
    func course() throws -> CourseStore {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        return try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
    }

    func write(_ store: CourseStore, _ title: String, _ text: String) throws -> URL {
        let url = store.newNoteURL(title: title, format: .markdown)
        try store.createNote(at: url, text: text)
        return url
    }

    /// The part under the heading is drawn and typeset; the note changing elsewhere draws it again.
    @Test func anEmbedDrawsTheOtherNoteAndFollowsIt() async throws {
        let store = try course()
        let other = try write(store, "정의 모음", "# 정의\n\n그래프는 $G=(V,E)$이다.\n\n# 다른 것\n\n빠짐")
        let rig = PreviewRig("앞\n\n![[정의 모음#정의]]\n\n![[없는 노트]]", embeds: NoteEmbedSource(store: store, own: nil))
        defer { rig.close() }
        await rig.settle()
        let embed = "return document.querySelector('div.embed:not(.embed-empty) .embed-body')?.textContent ?? ''"
        #expect((try await rig.js(embed) as? String)?.contains("그래프는") == true)
        #expect(try await rig.js("return document.querySelectorAll('div.embed .katex').length") as? Int == 1)
        #expect(try await rig.js("return document.body.textContent.includes('빠짐')") as? Bool == false)
        #expect(try await rig.js("return document.querySelector('div.embed-empty .embed-note')?.textContent") as? String
                == String(localized: .notesEmbedMissing))

        try store.write(NoteFile(url: other, meta: NoteMeta(id: nil)), text: "# 정의\n\n바뀐 내용")
        rig.revision += 1
        rig.show(rig.text)
        await rig.settle()
        #expect((try await rig.js(embed) as? String)?.contains("바뀐 내용") == true)
    }

    /// A link by ID finds its note in any course, whatever the note is named now; one to no note is drawn broken.
    @Test func aLinkByIDFindsItsNoteInAnyCourse() async throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let stores = try gist.courseStores()
        let here = try #require(stores.first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
        let there = try #require(stores.first { $0.url != here.url })
        let id = UUID(), gone = UUID()
        try NoteAdd(id: id, course: try there.load().model.course.id, title: "다른 과목 노트", body: "위\n\n정의할 것 ^c1\n")
            .run(ActionContext(gist: gist, device: UUID()))
        let text = "[[note:\(id.uuidString)]] [[note:\(gone.uuidString)|옛 노트]]\n\n![[note:\(id.uuidString)#^c1]]"
        let rig = PreviewRig(text, embeds: NoteEmbedSource(store: here, others: [there], own: nil))
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('a.wikilink:not(.missing)')?.textContent") as? String == "다른 과목 노트")
        #expect(try await rig.js("return document.querySelector('a.wikilink.missing')?.textContent") as? String == "옛 노트")
        #expect((try await rig.js("return document.querySelector('div.embed .embed-body')?.textContent ?? ''") as? String)?.contains("정의할 것") == true)
    }

    /// A title no note of the course has is drawn broken, until a note takes it.
    @Test func aTitleNoNoteHasIsBrokenUntilOneIsMade() async throws {
        let store = try course()
        _ = try write(store, "정의 모음", "# 정의")
        let rig = PreviewRig("[[정의 모음]] [[정의 모음.md|파일 이름]] [[새 노트]]\n\n앞 ![[새 노트]] 뒤", embeds: NoteEmbedSource(store: store, own: nil))
        defer { rig.close() }
        await rig.settle()
        let broken = "return [...document.querySelectorAll('a.missing')].map(a => a.textContent).join(',')"
        #expect(try await rig.js(broken) as? String == "새 노트,새 노트")

        _ = try write(store, "새 노트", "")
        rig.revision += 1
        rig.show(rig.text)
        await rig.settle()
        #expect(try await rig.js(broken) as? String == "")
    }

    /// Resting on a block reference shows its block in a card; moving off takes it away.
    @Test func aBlockReferenceShowsItsBlockOnHover() async throws {
        let store = try course()
        _ = try write(store, "보조정리", "위\n\n증명할 것 $x^2$ ^c1\n\n아래")
        let rig = PreviewRig("본문 [[보조정리#^c1|그 식]] 끝", embeds: NoteEmbedSource(store: store, own: nil))
        defer { rig.close() }
        await rig.settle()
        _ = try await rig.js("document.querySelector('a.wikilink').dispatchEvent(new MouseEvent('mouseover', {bubbles: true}))")
        try await Task.sleep(for: .milliseconds(600))
        #expect((try await rig.js("return document.querySelector('.ref-popover')?.textContent ?? ''") as? String)?.hasPrefix("증명할 것") == true)
        #expect(try await rig.js("return document.querySelector('.ref-popover').textContent.includes('아래')") as? Bool == false)
        #expect(try await rig.js("return document.querySelectorAll('.ref-popover .katex').length") as? Int == 1)
        _ = try await rig.js("document.querySelector('p').dispatchEvent(new MouseEvent('mouseover', {bubbles: true}))")
        try await Task.sleep(for: .milliseconds(500))
        #expect(try await rig.js("return document.querySelector('.ref-popover') == null") as? Bool == true)
    }
}
