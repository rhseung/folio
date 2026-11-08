#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import Observation
import WebKit

/// Debug-only: with `FOLIO_SNAPSHOT_DIR` set, the app walks through its screens, draws its own window into
/// PNGs there and quits. Lets screens be checked without screen-recording permission.
@MainActor @Observable
final class SnapshotDriver {
    static let shared = SnapshotDriver()
    static let directory = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_DIR"].map { URL(filePath: $0) }
    /// On this step (e.g. `course-notes`), web views are also drawn into `<step>-web-<n>.png`: `cacheDisplay` leaves
    /// them blank.
    static let webStep = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_WEB"]
    /// Steps to linger on (`course-sessions,settings-general`), so the real window (its buttons and glass too, which
    /// cacheDisplay leaves out) can be captured.
    static let holdSteps = Set((ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_HOLD"] ?? "").split(separator: ",").map(String.init))
    /// Shows the recording card in the sidebar as if a lecture were being recorded, without the microphone: `paused`
    /// shows it paused, a number (`0.3`) at that level.
    static let recording = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_RECORDING"] != nil
    static let recordingPaused = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_RECORDING"] == "paused"
    static let recordingLevel = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_RECORDING"].flatMap(Float.init) ?? 0.6
    /// A narrower window (e.g. `1100`) to catch labels that wrap or truncate once the columns squeeze.
    static let width = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_WIDTH"].flatMap(Double.init) ?? 1440
    /// How many tabs the window opens before the walk (`4`), to see the title row's tabs share and give up the row.
    static let tabs = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_TABS"].flatMap(Int.init) ?? 1
    /// How many panes the first two tabs hold (`2`, `3`), a lecture file and a quiz beside the page the walk moves (#62).
    static let panes = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_PANES"].flatMap(Int.init) ?? 1
    /// A note (its ID) to open, whose preview's first app link is then clicked as a user would, drawing where it went
    /// (`link-note-before`, `link-note`).
    static let noteLink = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_NOTE_LINK"].flatMap(UUID.init(uuidString:))
    /// `courses`: the first tab holds two courses side by side, the walk moving the left one and the second course's
    /// overview beside it, so both fold their section columns (#62).
    static let coursePanes = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_PANES"] == "courses"

    var section: CourseSection?
    /// Inside the units section: `detail` opens the first unit, `review` also opens its review sheet.
    var unitStep: String?
    /// Opens the Claude inspector on course screens. `cacheDisplay` can't draw inspectors, so no capture step uses it yet.
    var claudePanel = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_CLAUDE"] != nil
    /// Extra screens drawn outside the main window (the forms), run just before quitting.
    @ObservationIgnored var extraCaptures: ((URL) async -> Void)?
    var editCourse = false
    var editExam = false
    /// The extension of the classified file the materials page opens, one renderer at a time (`FileView`).
    var openFile: String?
    /// Set by the materials page when it found a file for `openFile`.
    var materialsOpenFile = false
    /// Asks Claude about the open PDF's page, as its button would.
    var askPage = false
    /// The view an open `.tex` switches to, as its bar's switch would.
    var texMode: NoteViewMode?
    var searchQuery: String?
    /// Opens every folded list column over its page (`FOLIO_SNAPSHOT_COLUMN=open`), as its corner button would.
    var columnOpen = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_COLUMN"] == "open"

    /// `links` are opened by their address at the end, each drawn as its step: what a click on such a link shows.
    func run(select: (Screen) -> Void, open: (AppLink) -> Void, courses: [UUID], semester: UUID?, links: [(String, AppLink)]) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: 900))
            // On screen for the hold step's capture; a restored frame can leave it off every display.
            window.center()
        }

        var plan: [(String, Screen, CourseSection?)] = [("today", .today, nil), ("grades", .grades, nil), ("requirements", .requirements, nil), ("people", .people, nil), ("codes", .codes, nil)]
        if let semester { plan.append(("semester", .semester(semester), nil)) }
        if let first = courses.first {
            plan += CourseSection.allCases.map { ("course-\($0)", .course(first), $0) }
        }
        for (name, destination, section) in plan {
            select(destination)
            self.section = section
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "\(name).png"))
            if name == "today" || name == "course-materials" { captureScrolled(to: directory.appending(path: "\(name)-full.png")) }
            if name == Self.webStep { await captureWebViews(to: directory, name: name) }
            if Self.holdSteps.contains(name) { try? await Task.sleep(for: .seconds(6)) }
        }
        if let first = courses.first {
            select(.course(first))
            section = .units
            for step in ["detail", "review"] {
                unitStep = step
                try? await Task.sleep(for: .seconds(1.5))
                capture(to: directory.appending(path: "course-units-\(step).png"))
            }
            // An open sheet keeps the app from terminating.
            unitStep = nil
            try? await Task.sleep(for: .seconds(1))

            section = .overview
            editCourse = true
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "course-edit.png"))
            editCourse = false
            try? await Task.sleep(for: .seconds(1))

            section = .exams
            editExam = true
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "course-exam-edit.png"))
            editExam = false
            try? await Task.sleep(for: .seconds(1))

            section = .materials
            // A format the fixture lacks leaves the list on screen and gets no picture.
            for ext in ["pdf", "tex", "md", "py", "png", "m4a", "docx", "hwp"] {
                openFile = ext
                try? await Task.sleep(for: .seconds(2.5))
                if materialsOpenFile { capture(to: directory.appending(path: "course-materials-\(ext).png")) }
                if materialsOpenFile, Self.webStep == "course-materials-\(ext)" { await captureWebViews(to: directory, name: "course-materials-\(ext)") }
                if materialsOpenFile, ext == "pdf" {
                    askPage = true
                    try? await Task.sleep(for: .seconds(2))
                    capture(to: directory.appending(path: "course-materials-pdf-ask.png"))
                    askPage = false
                    // Toggled, so the course view hears it close even when the panel was never asked open.
                    claudePanel = true
                    try? await Task.sleep(for: .seconds(0.3))
                    claudePanel = false
                }
                if materialsOpenFile, ext == "tex" {
                    // Split first, so it is also what the `.tex` is left remembering.
                    for mode in [NoteViewMode.read, .write, .split] {
                        texMode = mode
                        try? await Task.sleep(for: .seconds(1.5))
                        if mode != .split { capture(to: directory.appending(path: "course-materials-tex-\(mode.rawValue).png")) }
                    }
                    texMode = nil
                }
                if Self.holdSteps.contains("course-materials-\(ext)") { try? await Task.sleep(for: .seconds(6)) }
                openFile = nil
                try? await Task.sleep(for: .seconds(0.5))
            }
            searchQuery = ""
            try? await Task.sleep(for: .seconds(1))
            capture(to: directory.appending(path: "search-empty.png"))
            // Closed in between: the palette reads the query once, when it opens.
            searchQuery = nil
            try? await Task.sleep(for: .seconds(0.5))
            searchQuery = "matching"
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appending(path: "search.png"))
            searchQuery = nil
        }
        // Nil, so a course screen made for a link doesn't take the walk's last section over the link's.
        section = nil
        for (name, link) in links {
            open(link)
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "\(name).png"))
            if Self.holdSteps.contains(name) { try? await Task.sleep(for: .seconds(6)) }
        }
        if let note = Self.noteLink {
            open(AppLink(.note, note))
            try? await Task.sleep(for: .seconds(2.5))
            capture(to: directory.appending(path: "link-note-before.png"))
            await captureWebViews(to: directory, name: "link-note-before")
            await clickAppLink()
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appending(path: "link-note.png"))
        }
        // The panel's first app link, clicked as a user would, from a course with a chat (`FOLIO_SNAPSHOT_CLAUDE`).
        if claudePanel, let first = courses.first {
            select(.course(first))
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appending(path: "link-claude-before.png"))
            await captureWebViews(to: directory, name: "link-claude-before")
            await clickAppLink()
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "link-claude.png"))
        }
        for tab in SettingsTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
            select(.settings)
            try? await Task.sleep(for: .seconds(1.2))
            capture(to: directory.appending(path: "settings-\(tab).png"))
            if Self.holdSteps.contains("settings-\(tab)") { try? await Task.sleep(for: .seconds(6)) }
        }
        await extraCaptures?(directory)
        NSApp.terminate(nil)
    }

    func captureWebViews(to directory: URL, name: String) async {
        try? await Task.sleep(for: .seconds(2))
        func webViews(in view: NSView) -> [WKWebView] { (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews) }
        guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
        for (i, web) in webViews(in: root).enumerated() {
            guard let image = try? await web.takeSnapshot(configuration: nil), let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? png.write(to: directory.appending(path: "\(name)-web-\(i).png"))
        }
    }

    /// Pages run no script of their own; this runs in the app's world, where the panel's reader script runs.
    func clickAppLink() async {
        func webViews(in view: NSView) -> [WKWebView] { (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews) }
        guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
        let click = """
            const a = [...document.querySelectorAll('a[href^="folio://"]')].find(a => !a.href.startsWith('folio://action'));
            a?.click();
            return a != null;
            """
        for web in webViews(in: root) {
            if (try? await web.callAsyncJavaScript(click, contentWorld: .defaultClient)) as? Bool == true { return }
        }
    }

    // The whole of the tallest scroll view's content, past the window's bottom: Today's lower blocks.
    func captureScrolled(to url: URL) {
        func scrollViews(in view: NSView) -> [NSScrollView] { ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews) }
        guard let root = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil })?.contentView,
              let document = scrollViews(in: root).compactMap(\.documentView).max(by: { $0.bounds.height < $1.bounds.height }),
              let rep = document.bitmapImageRepForCachingDisplay(in: document.bounds) else { return }
        document.cacheDisplay(in: document.bounds, to: rep)
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func capture(to url: URL) {
        let window = NSApp.windows.first { $0.isVisible && $0.sheetParent == nil }
        // The main window's frame view, so the window's buttons are in the picture too; a sheet is its content alone.
        guard let view = window?.attachedSheet?.contentView ?? window?.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
