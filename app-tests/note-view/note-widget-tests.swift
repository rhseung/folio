import AppKit
import FolioDomain
import Foundation
import Testing
import WebKit
@testable import Folio

/// Widgets in the preview: each runs its course's `.folio/widgets/<id>.html` in a frame of the note's page, cut off
/// from the network and from the note.
@MainActor @Suite(.serialized, .timeLimit(.minutes(2)))
struct NoteWidgetTests {
    /// A course folder with one widget, and the preview showing a note in its `Notes`.
    static func preview(widget html: String?, height: CGFloat = 600, note: (UUID) -> String) throws -> (PreviewRig, UUID) {
        let course = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "EC4207 그래프 이론")
        let notes = course.appending(path: CourseFolder.notes.rawValue)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let id = UUID()
        if let html {
            let file = try #require(StandardLayout.widgetFile(id, noteFolder: notes))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(html.utf8).write(to: file)
        }
        return (PreviewRig(note(id), baseURL: notes, height: height), id)
    }

    static func block(_ id: UUID, height: Int = 200) -> String {
        "```cb-widget\n{\"id\": \"\(id.uuidString)\", \"height\": \(height)}\n```"
    }

    /// The first widget's frame, once its page has said how tall it is.
    static func frame(_ rig: PreviewRig) async throws -> WKFrameInfo {
        for _ in 0..<100 where rig.page.widgets.frames.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        return try #require(rig.page.widgets.frames.values.first)
    }

    /// Waits for the widget's page to set `window.done`, then reads `expression` there.
    static func value(_ rig: PreviewRig, _ expression: String) async throws -> Any? {
        let frame = try await Self.frame(rig)
        for _ in 0..<100 {
            if try await rig.page.view.callAsyncJavaScript("return window.done === true", in: frame, contentWorld: .page) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await rig.page.view.callAsyncJavaScript("return \(expression)", in: frame, contentWorld: .page)
    }

    static func text(_ rig: PreviewRig) async throws -> String? {
        let frame = try await Self.frame(rig)
        return try await rig.page.view.callAsyncJavaScript("return document.body.textContent", in: frame, contentWorld: .page) as? String
    }

    /// The height of the first widget's frame on the note's page: what its style says and what it's drawn at.
    static func heights(_ rig: PreviewRig) async throws -> (styled: Double, drawn: Double) {
        let read = "const f = document.querySelector('iframe.cb-widget'); return [parseFloat(f.style.height), f.getBoundingClientRect().height]"
        let both = try #require(try await rig.js(read) as? [Double])
        return (both[0], both[1])
    }

    @Test func runsTheWidgetFileInItsBlock() async throws {
        let html = "<!doctype html><button id=b>0</button><div style='height:300px'></div><script>window.done = true</script>"
        let (rig, id) = try Self.preview(widget: html) { "# Title\n\n" + Self.block($0, height: 240) + "\n\nAfter" }
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelector('iframe.cb-widget').src.includes(id)", ["id": id.uuidString]) as? Bool == true)
        #expect(try await Self.value(rig, "document.getElementById('b').textContent") as? String == "0")
        // The note's colors reach the page under the names note pages use.
        let accent = try await Self.value(rig, "getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()") as? String
        #expect(accent?.hasPrefix("#") == true)
        // The note's page can't reach into the widget's: the frame has an origin of its own.
        #expect(try await rig.js("try { return document.querySelector('iframe.cb-widget').contentDocument === null } catch { return true }") as? Bool == true)
    }

    /// The block takes the page's height in place, so scrolling the note never stops inside a short widget.
    @Test func theBlockFitsItsPage() async throws {
        let (rig, _) = try Self.preview(widget: "<!doctype html><div style='height:300px'></div>") { "Before\n\n" + Self.block($0, height: 200) + "\n\nAfter" }
        defer { rig.close() }
        await rig.settle()
        let heights = try await Self.heights(rig)
        #expect(heights.styled == 300 && heights.drawn == 300)
        let gap = try #require(try await rig.number("""
            const f = document.querySelector('iframe.cb-widget'), after = [...document.querySelectorAll('p')].at(-1)
            return after.getBoundingClientRect().top - f.getBoundingClientRect().bottom
            """))
        #expect(gap >= 0)
        // Shown again, the frame is kept with the height its page said.
        rig.show("Intro\n\n" + rig.text)
        await rig.settle()
        #expect(try await Self.heights(rig).styled == 300)
    }

    /// A page taller than the panel is drawn whole, so the note scrolls past it instead of stopping inside its frame.
    @Test func aLongPageIsDrawnWhole() async throws {
        let (rig, _) = try Self.preview(widget: "<!doctype html><div style='height:6000px'></div><script>window.done = true</script>", height: 600) {
            Self.block($0) + "\n\nAfter"
        }
        defer { rig.close() }
        await rig.settle()
        let heights = try await Self.heights(rig)
        #expect(heights.styled == 6000 && heights.drawn == 6000, "\(heights)")
        let inside = try await Self.value(rig, "[document.documentElement.scrollHeight, innerHeight]") as? [Double]
        #expect(inside?[0] == inside?[1], "\(String(describing: inside))")
    }

    @Test func theWidgetCannotReachTheNetwork() async throws {
        let html = """
        <!doctype html><script>
        window.violations = 0
        document.addEventListener('securitypolicyviolation', () => window.violations++)
        // Frames the widget makes inherit its sandbox: it can't reach into them, and their own code runs without
        // what the widget's page lost.
        const blank = document.createElement('iframe')
        document.documentElement.append(blank)
        try { window.blankPeers = typeof blank.contentWindow.RTCPeerConnection } catch { window.blankPeers = 'unreachable' }
        const written = document.createElement('iframe')
        written.srcdoc = '<script>parent.postMessage(typeof RTCPeerConnection, "*")<\\/script>'
        const loaded = new Promise(done => addEventListener('message', e => { window.writtenPeers = e.data; done() }))
        document.documentElement.append(written)
        const fetched = fetch('https://example.com/').then(() => window.fetched = 'loaded', () => window.fetched = 'blocked')
        Promise.allSettled([fetched, loaded]).then(() => setTimeout(() => window.done = true, 50))
        </script>
        """
        let (rig, _) = try Self.preview(widget: html) { Self.block($0) }
        defer { rig.close() }
        await rig.settle()
        #expect(try await Self.value(rig, "window.fetched") as? String == "blocked")
        #expect(try await Self.value(rig, "window.violations") as? Int ?? 0 > 0)
        #expect(try await Self.value(rig, "typeof RTCPeerConnection") as? String == "undefined")
        #expect(try await Self.value(rig, "window.blankPeers") as? String == "unreachable")
        #expect(try await Self.value(rig, "window.writtenPeers") as? String == "undefined")
    }

    /// A frame sent anywhere but a widget's page or blank is stopped: its address would carry data out.
    @Test func framesStayOnAWidgetOrBlank() throws {
        let page = try #require(URL(string: "\(WidgetFiles.scheme)://widget/\(UUID().uuidString)?k=a"))
        #expect(WidgetFiles.allows(page))
        #expect(WidgetFiles.allows(try #require(URL(string: page.absoluteString + "#step"))))
        #expect(WidgetFiles.allows(try #require(URL(string: "about:blank"))))
        #expect(!WidgetFiles.allows(try #require(URL(string: "https://example.com/?x=1"))))
        #expect(!WidgetFiles.allows(try #require(URL(string: "data:text/html,x"))))
        #expect(!WidgetFiles.allows(try #require(URL(string: "\(WidgetFiles.scheme)://elsewhere/x"))))
    }

    /// A widget can't send the note's page anywhere: a link it follows at the top is dropped.
    @Test func aWidgetCannotMoveTheNote() async throws {
        let html = "<!doctype html><script>try { top.location = 'https://example.com/' } catch {} window.done = true</script>"
        let (rig, _) = try Self.preview(widget: html) { "# Title\n\n" + Self.block($0) }
        defer { rig.close() }
        await rig.settle()
        _ = try await Self.value(rig, "1")
        try await Task.sleep(for: .milliseconds(200))
        // A page recycled from a note that followed a footnote keeps that anchor in its address; only a move counts.
        var address = try #require(rig.page.view.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        address.fragment = nil
        #expect(address.url == NotePreviewPage.shellURL)
        #expect(try await rig.js("return document.querySelector('h1')?.textContent") as? String == "Title")
    }

    /// A page sized by its frame, taller or shorter than it, takes the block's height instead of chasing the frame.
    @Test(arguments: [
        "<div style='height:100vh'></div><div style='height:16px'></div>", "<div style='height:50vh'></div>",
        "<div style='height:calc(600px - 100vh)'></div>", "<div style='height:200vh'></div>",
    ])
    func aPageSizedByItsFrameTakesTheBlocksHeight(body: String) async throws {
        let (rig, _) = try Self.preview(widget: "<!doctype html>" + body) { Self.block($0, height: 200) }
        defer { rig.close() }
        await rig.settle()
        try await Task.sleep(for: .milliseconds(500))
        let heights = try await Self.heights(rig)
        #expect(heights.styled == 200, "\(heights)")
    }

    /// Content that grows again while the block is following it (a font, an image, a chart drawn a frame later) isn't
    /// a page sized by its frame, and gets all of its height.
    @Test func aPageThatGrowsTwiceGetsAllOfItsHeight() async throws {
        let html = """
        <!doctype html><div id=d style='height:400px'></div>
        <script>addEventListener('resize', () => { if (innerHeight > 300) d.style.height = '420px' })</script>
        """
        let (rig, _) = try Self.preview(widget: html) { Self.block($0, height: 200) }
        defer { rig.close() }
        await rig.settle()
        try await Task.sleep(for: .milliseconds(500))
        let heights = try await Self.heights(rig)
        #expect(heights.styled == 420, "\(heights)")
    }

    /// A block written with no height still shows, so its page can say how tall it is.
    @Test(arguments: [0, -40])
    func aBlockWithNoHeightStillShows(height: Int) async throws {
        let (rig, _) = try Self.preview(widget: "<!doctype html><div style='height:100px'></div>") { Self.block($0, height: height) }
        defer { rig.close() }
        await rig.settle()
        #expect(try await Self.heights(rig).styled == 100)
    }

    @Test func keepsRunningWhenTheNoteIsShownAgain() async throws {
        let html = "<!doctype html><script>window.count = 1; window.done = true</script>"
        let (rig, id) = try Self.preview(widget: html) { Self.block($0) }
        defer { rig.close() }
        await rig.settle()
        _ = try await Self.value(rig, "window.count")
        _ = try await rig.page.view.callAsyncJavaScript("window.count = 5", in: try await Self.frame(rig), contentWorld: .page)
        rig.show("Intro\n\n" + Self.block(id) + "\n\nAfter")
        await rig.settle()
        #expect(try await Self.value(rig, "window.count") as? Int == 5)
        rig.show("No widget")
        await rig.settle()
        #expect(try await rig.js("return document.querySelectorAll('iframe').length") as? Int == 0)
        #expect(rig.page.widgets.frames.isEmpty)
    }

    @Test func aRewrittenFileStartsAnew() async throws {
        let (rig, id) = try Self.preview(widget: "<!doctype html><p>one</p>") { Self.block($0) }
        defer { rig.close() }
        await rig.settle()
        #expect(try await Self.text(rig) == "one")
        let file = try #require(rig.baseURL.flatMap { StandardLayout.widgetFile(id, noteFolder: $0) })
        try Data("<!doctype html><p>two</p>".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        rig.show("Intro\n\n" + Self.block(id))
        await rig.settle()
        #expect(rig.page.widgets.frames.count == 1)
        #expect(try await Self.text(rig) == "two")
    }

    @Test func aMissingFileSaysSo() async throws {
        let (rig, id) = try Self.preview(widget: nil) { Self.block($0) }
        defer { rig.close() }
        await rig.settle()
        #expect(try await Self.text(rig) == String(localized: .notesWidgetMissing(id.uuidString + ".html")))
    }

    @Test func aNoteOutsideItsCourseNotesSaysSo() async throws {
        let (rig, _) = try Self.preview(widget: nil) { Self.block($0) }
        defer { rig.close() }
        rig.baseURL = FileManager.default.temporaryDirectory
        rig.show(rig.text)
        await rig.settle()
        #expect(try await Self.text(rig) == String(localized: .notesWidgetNoCourse))
    }

    /// A widget in a table cell stays an inert placeholder: a cell is no place to run one.
    @Test func aWidgetInATableCellDoesNotRun() async throws {
        let (rig, _) = try Self.preview(widget: "<p>x") { id in
            let table = ["rows": [["cells": [["text": "```cb-widget\n{\"id\": \"\(id)\"}\n```"]]]]]
            let json = String(data: try! JSONSerialization.data(withJSONObject: table), encoding: .utf8)!
            return "```cb-table\n\(json)\n```"
        }
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelectorAll('iframe').length") as? Int == 0)
        #expect(rig.page.widgets.frame(for: "<table><tr><td><div class=\"cb-widget\" data-widget=\"\(UUID())\"></div></td></tr></table>") == nil)
    }

    @Test func aBlockThatDoesNotDecodeShowsItsText() async throws {
        let (rig, _) = try Self.preview(widget: nil) { _ in "```cb-widget\n{\"id\": 3}\n```" }
        defer { rig.close() }
        await rig.settle()
        #expect(try await rig.js("return document.querySelectorAll('iframe').length") as? Int == 0)
        #expect(try await rig.js("return document.body.textContent.includes('{\"id\": 3}')") as? Bool == true)
    }
}

/// How a widget's frame follows what its page says about its height.
@MainActor struct WidgetSizerTests {
    @Test func followsContent() {
        var sizer = WidgetSizer()
        #expect(sizer.report(page: 300, view: 200) == 300)
        #expect(sizer.report(page: 300, view: 300) == nil)
        #expect(sizer.report(page: 420, view: 300) == 420)
    }

    @Test func waitsForTheFrame() {
        var sizer = WidgetSizer()
        #expect(sizer.report(page: 0, view: 0) == nil)
        #expect(sizer.report(page: 120, view: 200) == 120)
    }

    /// `100vh`: the page changes by every change of the frame, so it keeps the height it started at.
    @Test func aPageSizedByItsFrameKeepsItsStart() {
        var sizer = WidgetSizer()
        #expect(sizer.report(page: 216, view: 200) == 216)
        #expect(sizer.report(page: 232, view: 216) == 232)
        #expect(sizer.report(page: 248, view: 232) == 200)
        #expect(sizer.report(page: 216, view: 200) == nil)
    }

    @Test func neverBelowAFloor() {
        var sizer = WidgetSizer()
        #expect(sizer.report(page: 2, view: 200) == 16)
    }
}
