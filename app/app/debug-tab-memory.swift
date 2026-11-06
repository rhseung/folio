#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import SwiftUI
import WebKit

/// Opens tabs one by one with every screen kept, for measuring what a kept tab costs (`WindowTabs.keep`). With
/// `FOLIO_TAB_MEMORY=<file>` and a fake `FOLIO_GIST`, the window opens `FOLIO_TAB_MEMORY_COUNT` tabs of
/// `FOLIO_TAB_MEMORY_KIND` (`note`: a note in the side-by-side view, `course`: a course's overview), writes a line
/// to the file as each has settled, then lets go of every tab behind and quits. Something outside reads the app's
/// and its web processes' footprints at each line: a note preview's page lives in a WebKit process of its own.
@MainActor enum TabMemoryProbe {
    static let environment = ProcessInfo.processInfo.environment
    static let file = environment["FOLIO_TAB_MEMORY"].map { URL(filePath: $0) }

    static func run(tabs: WindowTabs, workspace: Workspace) async {
        guard let file else { return }
        let count = environment["FOLIO_TAB_MEMORY_COUNT"].flatMap(Int.init) ?? 8
        let courses = workspace.currentCourses
        let links: [(AppLink, UUID)] = environment["FOLIO_TAB_MEMORY_KIND"] == "course"
            ? courses.map { (AppLink.course($0.id), $0.id) }
            : courses.flatMap { c in c.file.notes.map { (AppLink(.note, $0.id), c.id) } }
        guard !links.isEmpty else { return }
        tabs.policy = TabKeep.Policy(limit: environment["FOLIO_TAB_MEMORY_KEEP"].flatMap(Int.init) ?? 1000, idle: .infinity)
        var log = ""
        func mark(_ line: String) {
            log += line + "\n"
            // folio:not-an-action debug measurements, outside the GIST folder
            try? log.write(to: file, atomically: true, encoding: .utf8)
        }
        try? await Task.sleep(for: .seconds(4))
        mark("0")
        for i in 1...count {
            let (link, course) = links[(i - 1) % links.count]
            tabs.open(Navigator(Navigator.Entry(link: link, course: course)))
            try? await Task.sleep(for: .seconds(5))
            mark("\(i) alive=\(tabs.alive.count) webviews=\(webViews())")
        }
        // Back through every tab, as a reader going over them again: a kept page comes back into the window.
        for id in tabs.ids {
            tabs.select(id)
            try? await Task.sleep(for: .seconds(2))
        }
        try? await Task.sleep(for: .seconds(3))
        mark("cycled alive=\(tabs.alive.count) webviews=\(webViews())")
        tabs.dropBackground()
        try? await Task.sleep(for: .seconds(8))
        mark("dropped alive=\(tabs.alive.count) webviews=\(webViews())")
        try? await Task.sleep(for: .seconds(4))
        NSApp.terminate(nil)
    }

    /// What the window holds: web views (note previews) and text views (note sources).
    static func webViews() -> String {
        func count(_ view: NSView, _ kind: AnyClass) -> Int { (view.isKind(of: kind) ? 1 : 0) + view.subviews.reduce(0) { $0 + count($1, kind) } }
        let roots = NSApp.windows.compactMap(\.contentView)
        return "\(roots.reduce(0) { $0 + count($1, WKWebView.self) }) text=\(roots.reduce(0) { $0 + count($1, NSTextView.self) }) all=\(roots.reduce(0) { $0 + count($1, NSView.self) })"
    }
}
#endif
