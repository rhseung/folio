import AppKit
import FolioDomain
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

    init(_ text: String, baseURL: URL? = nil, editable: Bool = false, height: CGFloat = 600) {
        page = NotePreviewPage.take()
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
        page.show(text, baseURL: baseURL, math: .latex, accent: accent, dark: false)
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
    @Test func aRecycledPageStartsEmpty() async throws {
        let rig = PreviewRig("# One")
        await rig.settle()
        let page = rig.page
        rig.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await page.view.callAsyncJavaScript("return document.body.children.length", contentWorld: .defaultClient) as? Int == 0)
    }
}
