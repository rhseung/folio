#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import Observation
import SwiftUI
import WebKit

@MainActor @Observable
final class SnapshotDriver {
    static let shared = SnapshotDriver()
    static let directory = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_DIR"].map { URL(filePath: $0) }
    static let webStep = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_WEB"]
    static let holdSteps = Set((ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_HOLD"] ?? "").split(separator: ",").map(String.init))
    static let recording = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_RECORDING"] != nil
    static let recordingPaused = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_RECORDING"] == "paused"
    static let recordingLevel = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_RECORDING"].flatMap(Float.init) ?? 0.6
    static let width = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_WIDTH"].flatMap(Double.init) ?? 1440
    static let height = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_HEIGHT"].flatMap(Double.init) ?? 900
    static let tabs = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_TABS"].flatMap(Int.init) ?? 1
    static let panes = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_PANES"].flatMap(Int.init) ?? 1
    static let noteLink = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_NOTE_LINK"].flatMap(UUID.init(uuidString:))
    static let coursePanes = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_PANES"] == "courses"
    static let strip = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP"]
    static let stripEdit = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_EDIT"]
    static let stripNow = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_NOW"].flatMap { try? Date($0, strategy: .iso8601) }
    static let quickAdd = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_QUICK_ADD"] != nil
    static let split = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_SPLIT"]
    static let math = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_MATH"] != nil
    static let outline = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_OUTLINE"]

    var section: CourseSection?
    var unitStep: String?
    var claudePanel = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_CLAUDE"] != nil
    @ObservationIgnored var extraCaptures: ((URL) async -> Void)?
    var editCourse = false
    var editExam = false
    var editAssignmentMemo: String?
    var openFile: String?
    var materialsOpenFile = false
    var linkFile = false
    var askPage = false
    var texMode: NoteViewMode?
    var searchQuery: String?
    var columnOpen = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_COLUMN"] == "open"
    var strip: StripStep?
    var quickAddText: String?
    var quickAddOpen = false
    var quickAddDueOpen = false
    var quickAddRepeatOpen = false
    var quickAddPick: UUID?
    var mathPaletteOpen = false

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
        case remove(Int)
    }

    func run(select: (Screen) -> Void, open: (AppLink) -> Void, courses: [UUID], semester: UUID?, links: [(String, AppLink)]) async {
        guard let directory = Self.directory, !FirstRunDebug.walks else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: Self.height))
            window.center()
        }

        var plan: [(String, Screen, CourseSection?)] = [
            ("today", .today, nil), ("grades", .grades, nil), ("requirements", .requirements, nil), ("people", .people, nil),
            ("codes", .codes, nil),
            ("whats-new", .whatsNew, nil),
        ]
        if let semester { plan.append(("semester", .semester(semester), nil)) }
        if let first = courses.first {
            plan += CourseSection.allCases.map { ("course-\($0)", .course(first), $0) }
        }
        for (name, destination, section) in plan {
            select(destination)
            self.section = section
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "\(name).png"), popovers: name == "course-notes" && Self.outline != nil)
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

            section = .assignments
            editAssignmentMemo =
                "제출 안내\nhttps://lms.example.ac.kr/course/view.php?id=104729&section=assignment-submission-guidelines-and-rubric-2026-fall\n"
                + (1...14).map { "\($0). 문제 \($0)의 풀이 과정을 빠짐없이 적는다" }.joined(separator: "\n")
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "course-assignment-edit.png"))
            if Self.holdSteps.contains("course-assignment-edit") { try? await Task.sleep(for: .seconds(6)) }
            editAssignmentMemo = nil
            try? await Task.sleep(for: .seconds(1))

            section = .materials
            for ext in ["pdf", "tex", "md", "py", "png", "m4a", "docx", "hwp"] {
                openFile = ext
                try? await Task.sleep(for: .seconds(2.5))
                if materialsOpenFile { capture(to: directory.appending(path: "course-materials-\(ext).png")) }
                if materialsOpenFile, Self.webStep == "course-materials-\(ext)" {
                    await captureWebViews(to: directory, name: "course-materials-\(ext)")
                }
                if materialsOpenFile, ext == "pdf" {
                    askPage = true
                    try? await Task.sleep(for: .seconds(2))
                    capture(to: directory.appending(path: "course-materials-pdf-ask.png"))
                    askPage = false
                    claudePanel = true
                    try? await Task.sleep(for: .seconds(0.3))
                    claudePanel = false
                }
                if materialsOpenFile, ext == "tex" {
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
            linkFile = false
            try? await Task.sleep(for: .seconds(1))
            searchQuery = ""
            try? await Task.sleep(for: .seconds(1))
            capture(to: directory.appending(path: "search-empty.png"))
            // 팔레트는 열 때 한 번만 질의를 읽으므로 사이에 닫는다.
            searchQuery = nil
            try? await Task.sleep(for: .seconds(0.5))
            searchQuery = "matching"
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appending(path: "search.png"))
            searchQuery = nil
        }
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

    func runStrip(open: (AppLink) -> Void, lecture: AppLink) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
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
        func shot(_ name: String) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: true)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_SCREEN"] != nil else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        let steps: [(String, StripStep)] = [
            ("strip-idle", .page(edit.0)), ("strip-edit", .edit(edit.0, edit.1)), ("strip-pick", .range(range.0, range.1)),
            ("strip-menu", .choose), ("strip-saved", .save), ("strip-removed", .remove(min(range.0, range.1))),
        ]
        for (name, step) in steps {
            strip = step
            // 방금 저장한 구획은 1.6초 동안 강조되므로, 0.6초 뒤에 찍으면 강조된 모습이 찍힌다.
            try? await Task.sleep(for: .seconds(step == .save ? 0.6 : 2))
            await shot(name)
        }
        strip = nil
        NSApp.terminate(nil)
    }

    func runQuickAdd(open: (AppLink) -> Void, course: UUID, other: UUID?, named: String) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: Self.height))
            window.center()
        }
        func shot(_ name: String, popovers: Bool = false) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: popovers)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_QUICK_ADD"] == "screen" else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        let long = "Lab3 보고서 초안과 실험 데이터 정리, 그래프와 오차 분석, 참고 문헌 목록과 부록 표까지 모두 끝내고 조원 검토 받은 뒤 제출하기 다음 주 수요일 오후 6시까지"
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
        quickAddText = nil
        open(.place(.today))
        try? await Task.sleep(for: .seconds(3))
        for (name, text, pick) in [("empty", nil, nil), ("typed", "\(named) HW7 금", nil), ("picked", "\(named) HW7 금", other)]
            as [(String, String?, UUID?)]
        {
            quickAddText = text
            quickAddPick = pick
            quickAddOpen = true
            try? await Task.sleep(for: .seconds(pick == nil ? 3 : 4))
            await shot("quick-add-today-popover-\(name)", popovers: true)
            quickAddOpen = false
            quickAddPick = nil
            try? await Task.sleep(for: .seconds(1))
        }
        open(.course(course))
        try? await Task.sleep(for: .seconds(1))
        quickAddText = long
        section = .assignments
        try? await Task.sleep(for: .seconds(3))
        await shot("quick-add-assignments-long")
        section = .overview
        try? await Task.sleep(for: .seconds(1.5))
        let steps: [(String, String?, Bool)] = [
            ("empty", nil, false), ("short", "HW5 금 23:59", false),
            ("long", "Lab3 보고서 초안과 실험 데이터 정리, 그래프와 오차 분석까지 끝내고 제출 다음 주 수요일 오후 6시까지", false),
            ("wrapped", "확률과 통계 Lab3 보고서 매주 금 23:59", false), ("due-open", "HW5 금 23:59", true),
            ("repeat", "\(named) HW 매주 월수", false), ("repeat-open", "\(named) HW 격주 월수 18:00", false),
        ]
        for (name, text, dueOpen) in steps {
            quickAddText = text
            quickAddDueOpen = dueOpen
            quickAddRepeatOpen = name == "repeat-open"
            quickAddOpen = true
            try? await Task.sleep(for: .seconds(dueOpen || quickAddRepeatOpen ? 3.5 : 3))
            await shot("quick-add-course-\(name)", popovers: true)
            quickAddOpen = false
            quickAddDueOpen = false
            quickAddRepeatOpen = false
            try? await Task.sleep(for: .seconds(1))
        }
        quickAddText = nil
        NSApp.terminate(nil)
    }

    func runMath(open: (AppLink) -> Void, note: AppLink) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = NSApp.windows.first { $0.isVisible }
        window?.setContentSize(NSSize(width: Self.width, height: 900))
        window?.center()
        func shot(_ name: String, popovers: Bool = false) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: popovers)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_MATH"] == "screen" else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        open(note)
        func editors(in view: NSView) -> [SourceTextView] { (view as? SourceTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
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

    func runSplit(open: (AppLink) -> Void, lecture: AppLink, ask: () -> Void) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: Self.height))
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
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? png.write(to: directory.appending(path: "\(name)-web-\(i).png"))
        }
    }

    // 페이지는 자기 script를 실행하지 않는다. 이 코드는 패널의 reader script가 도는 앱의 content world에서 실행한다.
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

    func captureScrolled(to url: URL) {
        func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
        }
        guard let root = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil })?.contentView,
            let document = scrollViews(in: root).compactMap(\.documentView).max(by: { $0.bounds.height < $1.bounds.height }),
            let rep = document.bitmapImageRepForCachingDisplay(in: document.bounds)
        else { return }
        document.cacheDisplay(in: document.bounds, to: rep)
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func capture(to url: URL, popovers: Bool = false) {
        let window = NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && !$0.isPopover }
        guard let window, let view = window.attachedSheet?.contentView ?? window.contentView?.superview,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if popovers, window.attachedSheet == nil, let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for popover in NSApp.windows where popover.isVisible && popover.isPopover {
                guard let content = popover.contentView?.superview ?? popover.contentView,
                    let drawn = content.bitmapImageRepForCachingDisplay(in: content.bounds)
                else { continue }
                content.cacheDisplay(in: content.bounds, to: drawn)
                let origin = NSPoint(x: popover.frame.minX - window.frame.minX, y: popover.frame.minY - window.frame.minY)
                drawn.draw(
                    in: NSRect(origin: origin, size: content.bounds.size), from: .zero, operation: .sourceOver, fraction: 1,
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
#endif
