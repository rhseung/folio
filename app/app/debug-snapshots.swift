#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import Observation
import SwiftUI
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
    /// Only the page strip of a lecture with classes' pages (#147): its sections, a class's range changed, a range
    /// picked, the class menu and the range saved, as `strip-*.png`. Set to `from-to` (`19-21`) for the range picked.
    static let strip = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP"]
    /// The page a section's range is changed from and the page its end goes to (`16-19`), for `strip-edit`.
    static let stripEdit = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_EDIT"]
    /// The moment the strip walk is drawn at (`2026-11-04T10:00:00+09:00`), so today's class is the one a fixture's
    /// copy was given.
    static let stripNow = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_NOW"].flatMap { try? Date($0, strategy: .iso8601) }
    /// Only the quick-add line (#116): a long line typed on Today and a course's assignments, then the toolbar's popover
    /// opened on a course page empty, typed and long, as `quick-add-*.png`.
    static let quickAdd = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_QUICK_ADD"] != nil
    /// Only the split screen of a split lecture (#321): as it opens, then with a section's pages being changed from
    /// the thumbnails, as `split-*.png`. Set to `section-page` (`1-9`): the section whose header is pressed and the
    /// page ⇧-clicked after.
    static let split = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_SPLIT"]
    /// Only a formula's symbols (#392): the menu a bare `\` opens in a note, then the f(x) palette, as `math-*.png`.
    static let math = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_MATH"] != nil

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
    /// Opens the links sheet of a lecture file on the materials page, as its row's menu would.
    var linkFile = false
    /// Asks Claude about the open PDF's page, as its button would.
    var askPage = false
    /// The view an open `.tex` switches to, as its bar's switch would.
    var texMode: NoteViewMode?
    var searchQuery: String?
    /// Opens every folded list column over its page (`FOLIO_SNAPSHOT_COLUMN=open`), as its corner button would.
    var columnOpen = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_COLUMN"] == "open"
    /// What the open PDF's page strip does next, as a click on it would.
    var strip: StripStep?
    /// The line a quick-add field starts typed with when it appears, and whether the toolbar's popover is open.
    var quickAddText: String?
    var quickAddOpen = false
    /// Opens the deadline chip's calendar as the field appears.
    var quickAddDueOpen = false
    /// Opens the f(x) palette of the open note, as its button would.
    var mathPaletteOpen = false

    /// The split screen's section to take up from its header and the page its edge goes to, as clicks would.
    var splitEdit: SplitEdit?

    struct SplitEdit: Equatable {
        let section: Int
        let page: Int
    }

    enum StripStep: Equatable {
        case page(Int)
        case edit(Int, Int)
        case range(Int, Int)
        case choose
        case save
    }

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
            linkFile = true
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appending(path: "course-materials-links.png"))
            if Self.holdSteps.contains("course-materials-links") { try? await Task.sleep(for: .seconds(6)) }
            // An open sheet keeps the app from terminating.
            linkFile = false
            try? await Task.sleep(for: .seconds(1))
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

    /// The strip walk (`FOLIO_SNAPSHOT_STRIP`): opens `lecture` and steps through picking and saving a range.
    func runStrip(open: (AppLink) -> Void, lecture: AppLink) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            // No taller than the screen: the strip scrolls a page to its bottom edge, which was off a short screen and
            // out of the picture.
            let room = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: Self.width, height: min(900, room))), display: true)
            window.center()
        }
        func pair(_ text: String?, _ fallback: (Int, Int)) -> (Int, Int) {
            let bounds = (text ?? "").split(separator: "-").compactMap { Int($0) }
            return bounds.count == 2 ? (bounds[0], bounds[1]) : fallback
        }
        let range = pair(Self.strip, (19, 21)), edit = pair(Self.stripEdit, (16, 19))
        open(lecture)
        try? await Task.sleep(for: .seconds(3))
        // Glass and popovers draw only on screen: a `<step>.ready` file tells a script outside to capture the screen then.
        func shot(_ name: String) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: true)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_SCREEN"] != nil else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        let steps: [(String, StripStep)] = [
            ("strip-idle", .page(edit.0)), ("strip-edit", .edit(edit.0, edit.1)), ("strip-pick", .range(range.0, range.1)),
            ("strip-menu", .choose), ("strip-saved", .save),
        ]
        for (name, step) in steps {
            strip = step
            // The section just saved is lit for 1.6 seconds: drawn sooner, it still is.
            try? await Task.sleep(for: .seconds(step == .save ? 0.6 : 2))
            await shot(name)
        }
        strip = nil
        NSApp.terminate(nil)
    }

    /// The quick-add walk (`FOLIO_SNAPSHOT_QUICK_ADD`). `named` is the course's word for a line typed off its pages.
    func runQuickAdd(open: (AppLink) -> Void, course: UUID, named: String) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: 900))
            window.center()
        }
        // Glass and popovers draw only on screen: with `screen`, a `<step>.ready` file tells a script outside to capture
        // the window's area then.
        func shot(_ name: String, popovers: Bool = false) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: popovers)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_QUICK_ADD"] == "screen" else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        let long = "Lab3 보고서 초안과 실험 데이터 정리, 그래프와 오차 분석, 참고 문헌 목록과 부록 표까지 모두 끝내고 조원 검토 받은 뒤 제출하기 다음 주 수요일 오후 6시까지"
        // Away first: a page already shown keeps the field it laid out before the line was set.
        open(.course(course))
        section = .overview
        try? await Task.sleep(for: .seconds(1.5))
        for (name, text) in [("today-no-course", "HW2 보고서 내일"), ("today-long", "\(named) \(long)")] {
            quickAddText = text
            open(.place(.today))
            try? await Task.sleep(for: .seconds(3))
            await shot("quick-add-\(name)")
            open(.course(course))
            try? await Task.sleep(for: .seconds(1))
        }
        quickAddText = long
        section = .assignments
        try? await Task.sleep(for: .seconds(3))
        await shot("quick-add-assignments-long")
        section = .overview
        try? await Task.sleep(for: .seconds(1.5))
        // The popover is 440 wide: a long course name, a deadline, the repeat and a folder run onto a second chip row.
        let steps: [(String, String?, Bool)] = [
            ("empty", nil, false), ("short", "HW5 금 23:59", false),
            ("long", "Lab3 보고서 초안과 실험 데이터 정리, 그래프와 오차 분석까지 끝내고 제출 다음 주 수요일 오후 6시까지", false),
            ("wrapped", "확률과 통계 Lab3 보고서 매주 금 23:59", false), ("due-open", "HW5 금 23:59", true),
        ]
        for (name, text, dueOpen) in steps {
            quickAddText = text
            quickAddDueOpen = dueOpen
            quickAddOpen = true
            try? await Task.sleep(for: .seconds(dueOpen ? 3.5 : 3))
            await shot("quick-add-course-\(name)", popovers: true)
            quickAddOpen = false
            quickAddDueOpen = false
            try? await Task.sleep(for: .seconds(1))
        }
        quickAddText = nil
        NSApp.terminate(nil)
    }

    /// The math walk (`FOLIO_SNAPSHOT_MATH`): types `\` into a formula at the end of `note` as keys would, then opens
    /// the palette.
    func runMath(open: (AppLink) -> Void, note: AppLink) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = NSApp.windows.first { $0.isVisible }
        window?.setContentSize(NSSize(width: Self.width, height: 900))
        window?.center()
        // The popover's glass draws only on screen: with `screen`, a `<step>.ready` file tells a script outside to
        // capture the window's area then.
        func shot(_ name: String, popovers: Bool = false) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: popovers)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_MATH"] == "screen" else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        open(note)
        func editors(in view: NSView) -> [SourceTextView] { (view as? SourceTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
        // A first launch takes longer to lay the note out.
        var found: SourceTextView?
        for _ in 0..<20 where found == nil {
            try? await Task.sleep(for: .seconds(0.5))
            found = window?.contentView.flatMap { editors(in: $0).first }
        }
        try? await Task.sleep(for: .seconds(1))
        if let editor = found {
            window?.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            for key in "\n\n집합 $A " { editor.insertText(String(key), replacementRange: NSRange(location: NSNotFound, length: 0)) }
            editor.insertText("\\", replacementRange: NSRange(location: NSNotFound, length: 0))
            try? await Task.sleep(for: .seconds(2))
            await shot("math-menu")
            editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        }
        mathPaletteOpen = true
        try? await Task.sleep(for: .seconds(3))
        await shot("math-palette", popovers: true)
        mathPaletteOpen = false
        NSApp.terminate(nil)
    }

    /// The split walk (`FOLIO_SNAPSHOT_SPLIT`): opens `lecture`'s split screen, then changes a section from its header.
    func runSplit(open: (AppLink) -> Void, lecture: AppLink, ask: () -> Void) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: 900))
            window.center()
        }
        let bounds = (Self.split ?? "").split(separator: "-").compactMap { Int($0) }
        let edit = bounds.count == 2 ? SplitEdit(section: bounds[0], page: bounds[1]) : SplitEdit(section: 1, page: 9)
        open(lecture)
        try? await Task.sleep(for: .seconds(3))
        ask()
        func shot(_ name: String) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: true)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_SCREEN"] != nil else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        try? await Task.sleep(for: .seconds(3))
        await shot("split-idle")
        splitEdit = edit
        try? await Task.sleep(for: .seconds(2))
        await shot("split-edit")
        splitEdit = nil
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

    /// `popovers` also draws the app's popovers over the window where they stand: each is a window of its own, which
    /// drawing the main window leaves out.
    func capture(to url: URL, popovers: Bool = false) {
        let window = NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && !$0.isPopover }
        // The main window's frame view, so the window's buttons are in the picture too; a sheet is its content alone.
        guard let window, let view = window.attachedSheet?.contentView ?? window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if popovers, window.attachedSheet == nil, let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for popover in NSApp.windows where popover.isVisible && popover.isPopover {
                guard let content = popover.contentView?.superview ?? popover.contentView,
                      let drawn = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
                content.cacheDisplay(in: content.bounds, to: drawn)
                let origin = NSPoint(x: popover.frame.minX - window.frame.minX, y: popover.frame.minY - window.frame.minY)
                drawn.draw(in: NSRect(origin: origin, size: content.bounds.size), from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: nil)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
extension NSWindow {
    fileprivate var isPopover: Bool { className.contains("Popover") }
}

extension View {
    /// Drawn as in a key window (`FOLIO_SNAPSHOT_KEY`). The walk's windows are rarely key, since the Mac is in use
    /// while it runs, and a window that isn't draws its prominent buttons grey, a look they never have in use.
    @ViewBuilder func snapshotKey() -> some View {
        if ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_KEY"] != nil {
            environment(\.controlActiveState, .key)
        } else {
            self
        }
    }
}
#endif
