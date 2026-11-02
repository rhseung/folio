import AppKit
import FolioDomain
import Foundation
import Testing
import WebKit
@testable import Folio

/// Widgets in the read view: each runs its course's `.folio/widgets/<id>.html` in a web view cut off from the network.
@MainActor @Suite(.serialized)
struct NoteWidgetTests {
    /// A course folder with one widget, and the reader showing a note in its `Notes`.
    static func reader(widget html: String?, note: (UUID) -> String) throws -> (ReaderTextView, NSWindow, UUID) {
        let course = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "EC4207 그래프 이론")
        let notes = course.appending(path: CourseFolder.notes.rawValue)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let id = UUID()
        if let html {
            let file = try #require(StandardLayout.widgetFile(id, noteFolder: notes))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(html.utf8).write(to: file)
        }
        let view = ReaderTextView()
        view.delegate = view
        let window = NoteRender.host(view, width: 900, dark: false)
        view.baseURL = notes
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        view.show(note(id))
        NoteRender.layout(view)
        return (view, window, id)
    }

    static func block(_ id: UUID, height: Int = 200) -> String {
        "```cb-widget\n{\"id\": \"\(id.uuidString)\", \"height\": \(height)}\n```"
    }

    static func widgets(_ view: ReaderTextView) -> [WidgetAttachment] {
        var found: [WidgetAttachment] = []
        view.core.storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.core.storage.length)) { value, _, _ in
            if let widget = value as? WidgetAttachment { found.append(widget) }
        }
        return found
    }

    /// Waits for the page to set `window.done`, then reads `expression`.
    static func value(_ web: WKWebView, _ expression: String) async throws -> Any? {
        for _ in 0..<100 {
            if try await web.callAsyncJavaScript("return window.done === true", contentWorld: .page) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await web.callAsyncJavaScript("return \(expression)", contentWorld: .page)
    }

    static func fitted(_ web: WidgetWebView) async throws -> CGFloat {
        for _ in 0..<100 where web.pageHeight == nil { try await Task.sleep(for: .milliseconds(50)) }
        return try #require(web.pageHeight)
    }

    @Test func runsTheWidgetFileInItsBlock() async throws {
        let html = "<!doctype html><button id=b>0</button><div style='height:300px'></div><script>window.done = true</script>"
        let (view, _, id) = try Self.reader(widget: html) { "# Title\n\n" + Self.block($0, height: 240) + "\n\nAfter" }
        let widget = try #require(Self.widgets(view).first)
        #expect(widget.bounds.height == 240)
        let web = try #require(widget.view as? WidgetWebView)
        #expect(web.superview === view)
        #expect(!web.isHidden && web.frame.height == 240)
        #expect(web.file?.lastPathComponent == "\(id.uuidString).html")
        #expect(try await Self.value(web, "document.getElementById('b').textContent") as? String == "0")
        // The note's colors reach the page under the names note pages use.
        let accent = try await Self.value(web, "getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()") as? String
        #expect(accent?.hasPrefix("#") == true)
    }

    /// The block takes the page's height in place, so up-and-down scrolling never stops inside a widget.
    @Test func theBlockFitsItsPage() async throws {
        let html = "<!doctype html><div style='height:500px'></div>"
        let (view, _, _) = try Self.reader(widget: html) { "Before\n\n" + Self.block($0, height: 200) + "\n\nAfter" }
        let widget = try #require(Self.widgets(view).first)
        let web = try #require(widget.view as? WidgetWebView)
        #expect(try await Self.fitted(web) == 500)
        #expect(widget.bounds.height == 500)
        NoteRender.layout(view)
        #expect(web.frame.height == 500)
        let after = try #require(NoteRender.caret(view, at: (view.string as NSString).range(of: "After").location))
        #expect(view.textContainerOrigin.y + after.minY >= web.frame.maxY)
        // Rendered again, the block starts at the page's height rather than the one written in it.
        view.show("Intro\n\n" + view.core.shown!)
        NoteRender.layout(view)
        #expect(Self.widgets(view).first?.bounds.height == 500)
    }

    @Test func theWidgetCannotReachTheNetwork() async throws {
        let html = """
        <!doctype html><script>
        window.violations = 0
        document.addEventListener('securitypolicyviolation', () => window.violations++)
        fetch('https://example.com/').then(() => window.fetched = 'loaded', () => window.fetched = 'blocked')
          .finally(() => setTimeout(() => window.done = true, 50))
        </script>
        """
        let (view, _, _) = try Self.reader(widget: html) { Self.block($0) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        #expect(try await Self.value(web, "window.fetched") as? String == "blocked")
        #expect(try await Self.value(web, "window.violations") as? Int ?? 0 > 0)
        #expect(try await Self.value(web, "typeof RTCPeerConnection") as? String == "undefined")
    }

    /// A frame sent anywhere but blank is stopped: its address would carry data out.
    @Test func framesStayOnThePageOrBlank() throws {
        let page = WidgetScheme.page, out = try #require(URL(string: "https://example.com/?x=1"))
        for main in [true, false] {
            #expect(WidgetWebView.allows(page, mainFrame: main))
            #expect(WidgetWebView.allows(try #require(URL(string: page.absoluteString + "#step")), mainFrame: main))
            #expect(!WidgetWebView.allows(out, mainFrame: main))
            #expect(!WidgetWebView.allows(try #require(URL(string: "data:text/html,x")), mainFrame: main))
        }
        let blank = try #require(URL(string: "about:blank"))
        #expect(WidgetWebView.allows(blank, mainFrame: false))
        #expect(!WidgetWebView.allows(blank, mainFrame: true))
    }

    /// A page sized by its view, taller or shorter than it, takes the block's height instead of chasing the view.
    @Test(arguments: ["<div style='height:100vh'></div><div style='height:16px'></div>", "<div style='height:50vh'></div>"])
    func aPageSizedByItsViewTakesTheBlocksHeight(body: String) async throws {
        let (view, _, _) = try Self.reader(widget: "<!doctype html>" + body) { Self.block($0, height: 200) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        _ = try await Self.fitted(web)
        for _ in 0..<10 { NoteRender.layout(view); try await Task.sleep(for: .milliseconds(50)) }
        #expect(web.pageHeight == 200)
        #expect(web.frame.height == 200)
    }

    @Test func aLongPageGetsAllOfItsHeight() async throws {
        let (view, _, _) = try Self.reader(widget: "<!doctype html><div style='height:6000px'></div>") { Self.block($0) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        #expect(try await Self.fitted(web) == 6000)
    }

    @Test func keepsItsViewWhenTheNoteIsRenderedAgain() async throws {
        let html = "<!doctype html><script>window.count = 1; window.done = true</script>"
        let (view, _, id) = try Self.reader(widget: html) { Self.block($0) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        _ = try await Self.value(web, "window.count")
        _ = try await web.callAsyncJavaScript("window.count = 5", contentWorld: .page)
        view.show("Intro\n\n" + Self.block(id))
        NoteRender.layout(view)
        let again = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        #expect(again === web)
        #expect(try await Self.value(again, "window.count") as? Int == 5)
        view.show("No widget")
        NoteRender.layout(view)
        #expect(web.superview == nil)
    }

    static func text(_ web: WKWebView) async throws -> String? {
        for _ in 0..<100 where try await web.callAsyncJavaScript("return document.readyState", contentWorld: .page) as? String != "complete" {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await web.callAsyncJavaScript("return document.body.textContent", contentWorld: .page) as? String
    }

    @Test func aMissingFileSaysSo() async throws {
        let (view, _, id) = try Self.reader(widget: nil) { Self.block($0) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        #expect(try await Self.text(web) == String(localized: .notesWidgetMissing(id.uuidString + ".html")))
    }

    @Test func aNoteOutsideItsCourseNotesSaysSo() async throws {
        let (view, _, _) = try Self.reader(widget: nil) { Self.block($0) }
        view.baseURL = FileManager.default.temporaryDirectory
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        NoteRender.layout(view)
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        #expect(web.file == nil)
        #expect(try await Self.text(web) == String(localized: .notesWidgetNoCourse))
    }

    @Test(arguments: [(100, false), (3000, true)])
    func scrollsOnlySideways(width: Int, wide: Bool) async throws {
        let html = "<!doctype html><div style='width:\(width)px;height:40px'></div><script>const s = 1; window.done = true</script>"
        let (view, _, _) = try Self.reader(widget: html) { Self.block($0) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        // A widget may name things as the injected scripts do.
        #expect(try await Self.value(web, "s") as? Int == 1)
        _ = try await Self.fitted(web)
        #expect(web.wide == wide)
    }

    @Test func aRewrittenFileStartsAnew() async throws {
        let (view, _, id) = try Self.reader(widget: "<!doctype html><p>one</p>") { Self.block($0) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        let file = try #require(web.file)
        try Data("<!doctype html><p>two</p>".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        view.show("Intro\n\n" + Self.block(id))
        NoteRender.layout(view)
        let again = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        #expect(again !== web)
        #expect(try await Self.text(again) == "two")
    }

    @Test func aBlockThatDoesNotDecodeShowsItsText() throws {
        let (view, _, _) = try Self.reader(widget: nil) { _ in "```cb-widget\n{\"id\": 3}\n```" }
        #expect(Self.widgets(view).isEmpty)
        #expect(NoteReaderTests.codes(view.core.storage).map(\.code.string) == ["{\"id\": 3}"])
    }
}
