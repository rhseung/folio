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
    var accent = CourseAccent.presets[0].accent
    /// Stands for the workspace's `notesRevision`, which another note's change bumps.
    var revision = 0

    init(_ text: String, baseURL: URL? = nil, editable: Bool = false, height: CGFloat = 600, embeds: NoteEmbedSource? = nil) {
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
        page.show(text, baseURL: baseURL, math: .latex, accent: accent, dark: false, revision: revision)
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
