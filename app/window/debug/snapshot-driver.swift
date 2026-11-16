#if DEBUG && os(macOS)
import AppKit
import FolioActions
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

    @ObservationIgnored var extraCaptures: ((URL) async -> Void)?
    // 창이 열리면 `ItemSheets`가 자기 시트를 띄우는 함수로 채운다.
    @ObservationIgnored var present: @MainActor (ItemSheet?) -> Void = { _ in }
    // 창이 `\.screenRequests`로 화면에 내려 준다. 환경 변수로 켠 요청은 실행 내내 남는다. 스냅숏을 찍지 않는 디버그 실행에는
    // 아무 요청도 없어야 화면이 평소처럼 동작한다.
    var requests = SnapshotDriver.standing

    static let claude = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_CLAUDE"] != nil
    static let standing: Set<ScreenRequest> = {
        guard directory != nil else { return [] }
        var standing: Set<ScreenRequest> = [.quiz]
        if ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_COLUMN"] == "open" { standing.insert(.column) }
        if claude { standing.insert(.claude) }
        if outline == "popover" { standing.insert(.outlinePopover) }
        return standing
    }()

    func ask(_ asked: ScreenRequest...) { requests = Self.standing.union(asked) }

    func run(workspace: Workspace, open: (AppLink) -> Void, links: [(String, AppLink)]) async {
        guard let directory = Self.directory, !FirstRunDebug.walks else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: Self.height))
            window.center()
        }
        func step(_ name: String, _ link: AppLink? = nil, sheet: ItemSheet? = nil, asks: [ScreenRequest] = [], wait: Double = 1.5) async {
            requests = Self.standing.union(asks)
            if let link { open(link) }
            if let sheet { present(sheet) }
            try? await Task.sleep(for: .seconds(wait))
            capture(to: directory.appending(path: "\(name).png"), popovers: name == "course-notes" && Self.outline != nil)
            if name == "today" || name == "course-materials" { captureScrolled(to: directory.appending(path: "\(name)-full.png")) }
            if name == Self.webStep { await captureWebViews(to: directory, name: name) }
            if Self.holdSteps.contains(name) { try? await Task.sleep(for: .seconds(6)) }
            if sheet != nil {
                present(nil)
                try? await Task.sleep(for: .seconds(1))
            }
            requests = Self.standing
        }

        let spring = workspace.transcript.semesters.first { $0.year == 2026 && $0.term == .spring }
        for (name, kind) in [
            ("today", AppLink.Kind.today), ("grades", .grades), ("requirements", .requirements), ("people", .people),
            ("codes", .codes), ("whats-new", .whatsNew),
        ] {
            await step(name, .place(kind), asks: kind == .grades ? spring.map { [.expand($0.id)] } ?? [] : [])
        }
        if let semester = workspace.currentSemester { await step("semester", AppLink(.semester, semester.id)) }
        if let course = workspace.currentCourses.first?.id {
            let note = workspace.course(course)?.file.notes.first.map { AppLink(.note, $0.id) }
            for page in AppLink.CoursePage.allCases {
                await step("course-\(page)", page == .notes ? note ?? .course(course, page: page) : .course(course, page: page))
            }
            await courseSteps(course, workspace: workspace, open: open, step: step)
        }
        for (name, link) in links { await step(name, link) }
        if let note = Self.noteLink {
            open(AppLink(.note, note))
            try? await Task.sleep(for: .seconds(2.5))
            capture(to: directory.appending(path: "link-note-before.png"))
            await captureWebViews(to: directory, name: "link-note-before")
            await clickAppLink()
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appending(path: "link-note.png"))
        }
        if Self.claude, let course = workspace.currentCourses.first?.id {
            open(.course(course))
            try? await Task.sleep(for: .seconds(2))
            capture(to: directory.appending(path: "link-claude-before.png"))
            await captureWebViews(to: directory, name: "link-claude-before")
            await clickAppLink()
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "link-claude.png"))
        }
        for tab in AppLink.SettingsPage.allCases { await step("settings-\(tab)", .settings(tab), wait: 1.2) }
        await extraCaptures?(directory)
        NSApp.terminate(nil)
    }

    // 과목 안의 단계는 사용자가 가는 길(항목 링크와 창의 시트)로만 연다. 화면은 스냅숏을 따로 알지 않는다.
    private func courseSteps(
        _ course: UUID, workspace: Workspace, open: (AppLink) -> Void,
        step: (String, AppLink?, ItemSheet?, [ScreenRequest], Double) async -> Void
    ) async {
        guard let directory = Self.directory, var file = workspace.course(course)?.file else { return }
        if let unit = UnitTree.outline(file.units).first?.unit.id {
            await step("course-units-detail", AppLink(.unit, unit), nil, [], 1.5)
            await step("course-units-review", nil, .review(course: course, unit: unit), [], 1.5)
        }
        await step("course-edit", .course(course), .course(course), [], 1.5)
        if let exam = file.exams.first {
            await step("course-exam-edit", .course(course, page: .exams), .exam(course: course, exam: exam.id), [], 1.5)
        }
        if let assignment = file.assignments.first {
            // 낮은 창에서 시트가 넘기는 모습을 보도록 긴 메모를 잠시 쓰고, 찍은 뒤 되돌린다. 가짜 폴더에서만 돈다.
            let memo =
                "제출 안내\nhttps://lms.example.ac.kr/course/view.php?id=104729&section=assignment-submission-guidelines-and-rubric-2026-fall\n"
                + (1...14).map { "\($0). 문제 \($0)의 풀이 과정을 빠짐없이 적는다" }.joined(separator: "\n")
            workspace.run(AssignmentSave(course: course, assignment: assignment.id, memo: .set(memo)))
            await step(
                "course-assignment-edit", .course(course, page: .assignments), .assignment(course: course, assignment: assignment.id), [],
                1.5)
            workspace.run(AssignmentSave(course: course, assignment: assignment.id, memo: .set(assignment.memo)))
        }

        open(.course(course, page: .materials))
        if file.materials.isEmpty, workspace.run(MaterialTrack(course: course)) != nil, let tracked = workspace.course(course)?.file {
            file = tracked
        }
        for ext in ["pdf", "tex", "md", "py", "png", "m4a", "docx", "hwp"] {
            let shown = file.materials.first {
                !$0.isFolder && ($0.path as NSString).pathExtension.lowercased() == ext && $0.status == .classified
            }
            guard let shown else { continue }
            let name = "course-materials-\(ext)"
            open(AppLink(.material, shown.id))
            try? await Task.sleep(for: .seconds(2.5))
            capture(to: directory.appending(path: "\(name).png"))
            if Self.webStep == name { await captureWebViews(to: directory, name: name) }
            if ext == "pdf" {
                ask(.askPage)
                try? await Task.sleep(for: .seconds(2))
                capture(to: directory.appending(path: "course-materials-pdf-ask.png"))
                ask(.claude)
                try? await Task.sleep(for: .seconds(0.3))
                ask()
            }
            if ext == "tex" {
                for mode in [NoteViewMode.read, .write, .split] {
                    ask(.viewMode(mode))
                    try? await Task.sleep(for: .seconds(1.5))
                    if mode != .split { capture(to: directory.appending(path: "course-materials-tex-\(mode.rawValue).png")) }
                }
                ask()
            }
            if Self.holdSteps.contains(name) { try? await Task.sleep(for: .seconds(6)) }
            open(.course(course, page: .materials))
            try? await Task.sleep(for: .seconds(0.5))
        }
        if let linked = file.materials.first(where: { $0.role == .lecture && $0.isPDF }) ?? file.materials.first {
            await step("course-materials-links", nil, .material(MaterialSheetRequest(course: course, material: linked.id)), [], 2)
        }

        ask(.search(""))
        try? await Task.sleep(for: .seconds(1))
        capture(to: directory.appending(path: "search-empty.png"))
        // 팔레트는 열 때 한 번만 질의를 읽으므로 사이에 닫는다.
        ask()
        try? await Task.sleep(for: .seconds(0.5))
        ask(.search("matching"))
        try? await Task.sleep(for: .seconds(2))
        capture(to: directory.appending(path: "search.png"))
        ask()
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
        let steps: [(String, ScreenRequest.StripStep)] = [
            ("strip-idle", .page(edit.0)), ("strip-edit", .edit(edit.0, edit.1)), ("strip-pick", .range(range.0, range.1)),
            ("strip-menu", .choose), ("strip-saved", .save), ("strip-removed", .remove(min(range.0, range.1))),
        ]
        for (name, step) in steps {
            ask(.strip(step))
            // 방금 저장한 구획은 1.6초 동안 강조되므로, 0.6초 뒤에 찍으면 강조된 모습이 찍힌다.
            try? await Task.sleep(for: .seconds(step == .save ? 0.6 : 2))
            await shot(name)
        }
        ask()
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
        try? await Task.sleep(for: .seconds(1.5))
        for (name, text) in [("today-no-course", "HW2 보고서 내일"), ("today-long", "\(named) \(long)")] {
            ask(.quickAdd(.init(text: text)))
            open(.place(.today))
            try? await Task.sleep(for: .seconds(3))
            await shot("quick-add-\(name)")
            open(.course(course))
            try? await Task.sleep(for: .seconds(1))
        }
        ask()
        open(.place(.today))
        try? await Task.sleep(for: .seconds(3))
        for (name, text, pick) in [("empty", nil, nil), ("typed", "\(named) HW7 금", nil), ("picked", "\(named) HW7 금", other)]
            as [(String, String?, UUID?)]
        {
            ask(.quickAdd(.init(text: text, course: pick)), .quickAddPopover)
            try? await Task.sleep(for: .seconds(pick == nil ? 3 : 4))
            await shot("quick-add-today-popover-\(name)", popovers: true)
            ask()
            try? await Task.sleep(for: .seconds(1))
        }
        open(.course(course))
        try? await Task.sleep(for: .seconds(1))
        ask(.quickAdd(.init(text: long)))
        open(.course(course, page: .assignments))
        try? await Task.sleep(for: .seconds(3))
        await shot("quick-add-assignments-long")
        open(.course(course))
        try? await Task.sleep(for: .seconds(1.5))
        let steps: [(String, String?, Bool)] = [
            ("empty", nil, false), ("short", "HW5 금 23:59", false),
            ("long", "Lab3 보고서 초안과 실험 데이터 정리, 그래프와 오차 분석까지 끝내고 제출 다음 주 수요일 오후 6시까지", false),
            ("wrapped", "확률과 통계 Lab3 보고서 매주 금 23:59", false), ("due-open", "HW5 금 23:59", true),
            ("repeat", "\(named) HW 매주 월수", false), ("repeat-open", "\(named) HW 격주 월수 18:00", false),
        ]
        for (name, text, dueOpen) in steps {
            let repeats = name == "repeat-open"
            ask(.quickAdd(.init(text: text, due: dueOpen, repeats: repeats)), .quickAddPopover)
            try? await Task.sleep(for: .seconds(dueOpen || repeats ? 3.5 : 3))
            await shot("quick-add-course-\(name)", popovers: true)
            ask()
            try? await Task.sleep(for: .seconds(1))
        }
        ask()
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
        ask(.mathPalette)
        try? await Task.sleep(for: .seconds(3))
        await shot("math-palette", popovers: true)
        ask()
        NSApp.terminate(nil)
    }

    func runSplit(open: (AppLink) -> Void, lecture: AppLink, split: () -> Void) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: Self.height))
            window.center()
        }
        let bounds = (Self.split ?? "").split(separator: "-").compactMap { Int($0) }
        let edit =
            bounds.count == 2
            ? ScreenRequest.SplitEdit(section: bounds[0], page: bounds[1]) : ScreenRequest.SplitEdit(section: 1, page: 9)
        open(lecture)
        try? await Task.sleep(for: .seconds(3))
        split()
        func shot(_ name: String) async {
            capture(to: directory.appending(path: "\(name).png"), popovers: true)
            guard ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_STRIP_SCREEN"] != nil else { return }
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? Data().write(to: directory.appending(path: "\(name).ready"))
            try? await Task.sleep(for: .seconds(3))
        }
        try? await Task.sleep(for: .seconds(3))
        await shot("split-idle")
        ask(.splitEdit(edit))
        try? await Task.sleep(for: .seconds(2))
        await shot("split-edit")
        ask()
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
