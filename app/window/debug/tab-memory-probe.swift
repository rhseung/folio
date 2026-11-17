#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import SwiftUI
import WebKit

@MainActor enum TabMemoryProbe {
    static let environment = ProcessInfo.processInfo.environment
    static let file = environment["FOLIO_TAB_MEMORY"].map { URL(filePath: $0) }

    static func run(tabs: WindowTabs, workspace: Workspace) async {
        guard let file else { return }
        let count = environment["FOLIO_TAB_MEMORY_COUNT"].flatMap(Int.init) ?? 8
        let courses = workspace.currentCourses
        let links: [(AppLink, UUID)] =
            switch environment["FOLIO_TAB_MEMORY_KIND"] {
            case "course": courses.map { (AppLink.course($0.id), $0.id) }
            case "pdf":
                courses.flatMap { c in
                    c.file.materials.filter { $0.path.lowercased().hasSuffix(".pdf") }.map { (AppLink(.material, $0.id), c.id) }
                }
            default: courses.flatMap { c in c.file.notes.map { (AppLink(.note, $0.id), c.id) } }
            }
        guard !links.isEmpty else { return }
        tabs.policy = TabKeep.Policy(limit: environment["FOLIO_TAB_MEMORY_KEEP"].flatMap(Int.init) ?? 1000, idle: .infinity)
        var log = ""
        func mark(_ line: String) {
            log += "\(line) footprint=\(MemoryProbe.megabytes())\n"
            // folio:not-an-action debug measurements, outside the GIST folder
            try? log.write(to: file, atomically: true, encoding: .utf8)
        }
        try? await Task.sleep(for: .seconds(4))
        mark("0")
        for i in 1...count {
            let (link, course) = links[(i - 1) % links.count]
            tabs.open(Navigator(Navigator.Entry(link: link, course: course)))
            try? await Task.sleep(for: .seconds(5))
            if environment["FOLIO_TAB_MEMORY_EDIT"] != nil { type(into: i) }
            mark("\(i) alive=\(tabs.alive.count) webviews=\(webViews())")
        }
        for id in tabs.ids {
            tabs.select(id)
            try? await Task.sleep(for: .seconds(2))
        }
        try? await Task.sleep(for: .seconds(3))
        mark("cycled alive=\(tabs.alive.count) webviews=\(webViews())")
        tabs.dropBackground()
        try? await Task.sleep(for: .seconds(8))
        mark("dropped alive=\(tabs.alive.count) webviews=\(webViews())")
        tabs.closeOthers(than: tabs.ids[0])
        try? await Task.sleep(for: .seconds(10))
        mark("closed alive=\(tabs.alive.count) webviews=\(webViews())")
        // 바깥에서 `heap`으로 닫은 탭의 편집기와 모델이 남았는지 셀 수 있게 머문다.
        if let hold = environment["FOLIO_TAB_MEMORY_HOLD"].flatMap(Double.init) {
            // folio:not-an-action debug measurements, outside the GIST folder
            try? "\(ProcessInfo.processInfo.processIdentifier)".write(
                to: file.appendingPathExtension("ready"), atomically: true, encoding: .utf8)
            try? await Task.sleep(for: .seconds(hold))
        }
        try? await Task.sleep(for: .seconds(4))
        NSApp.terminate(nil)
    }

    // 사람이 치는 것처럼 되돌리기 기록에 남도록 `insertText`로 넣는다.
    private static func type(into tab: Int) {
        func find(_ view: NSView) -> NoteTextView? {
            if let text = view as? NoteTextView, text.window != nil, !text.isHiddenOrHasHiddenAncestor { return text }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let text = NSApp.windows.compactMap(\.contentView).lazy.compactMap(find).first else { return }
        text.window?.makeFirstResponder(text)
        for _ in 0..<200 { text.insertText("memory probe \(tab) ", replacementRange: NSRange(location: 0, length: 0)) }
    }

    static func webViews() -> String {
        func count(_ view: NSView, _ kind: AnyClass) -> Int {
            (view.isKind(of: kind) ? 1 : 0) + view.subviews.reduce(0) { $0 + count($1, kind) }
        }
        let roots = NSApp.windows.compactMap(\.contentView)
        return
            "\(roots.reduce(0) { $0 + count($1, WKWebView.self) }) text=\(roots.reduce(0) { $0 + count($1, NSTextView.self) }) all=\(roots.reduce(0) { $0 + count($1, NSView.self) })"
    }
}
#endif
