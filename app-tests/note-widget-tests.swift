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

    @Test func runsTheWidgetFileInItsBlock() async throws {
        let html = "<!doctype html><button id=b>0</button><script>window.done = true</script>"
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

    @Test func aMissingFileSaysSo() async throws {
        let (view, _, id) = try Self.reader(widget: nil) { Self.block($0) }
        let web = try #require(Self.widgets(view).first?.view as? WidgetWebView)
        for _ in 0..<100 where try await web.callAsyncJavaScript("return document.readyState", contentWorld: .page) as? String != "complete" {
            try await Task.sleep(for: .milliseconds(50))
        }
        let text = try await web.callAsyncJavaScript("return document.body.textContent", contentWorld: .page) as? String
        #expect(text?.contains(id.uuidString) == true)
    }
}
