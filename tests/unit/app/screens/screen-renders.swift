import AppKit
import FolioDomain
import FolioFixtures
import SwiftUI
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct ScreenRenders {
    nonisolated static let env = ProcessInfo.processInfo.environment
    nonisolated static let folder = env["FOLIO_RENDER_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    static let sizes: [(name: String, width: CGFloat, height: CGFloat?)] = list("FOLIO_RENDER_SIZES", or: "1180,720").compactMap { spec in
        let parts = spec.split(separator: "x").compactMap { Double($0) }
        guard let width = parts.first else { return nil }
        return (spec, width, parts.count > 1 ? parts[1] : nil)
    }
    static let screens = list("FOLIO_RENDER_SCREENS", or: "")

    nonisolated static func list(_ key: String, or fallback: String) -> [String] {
        (env[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    nonisolated static let scenarios = Scenario.allCases.filter { s in
        list("FOLIO_RENDER_SCENARIOS", or: "").isEmpty || list("FOLIO_RENDER_SCENARIOS", or: "").contains(s.rawValue)
    }

    @Test(.enabled(if: folder != nil), arguments: scenarios)
    func screens(_ scenario: Scenario) async throws {
        let folder = try #require(Self.folder).appending(path: scenario.rawValue)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let workspace = try Workspace.scenario(scenario)
        func wanted(_ screen: Screen) -> Bool { Self.screens.isEmpty || Self.screens.contains { screen.name.hasPrefix($0) } }

        for batch in batches(workspace) {
            let pages = batch.pages.filter(wanted), sheets = batch.sheets.filter(wanted)
            guard !pages.isEmpty || !sheets.isEmpty else { continue }
            batch.setup()
            var jobs: [RenderJob] = []
            for page in pages {
                for size in Self.sizes {
                    for scheme in [ColorScheme.light, .dark] {
                        jobs.append(
                            RenderJob(
                                name: "\(page.name)-\(size.name)-\(scheme.label)", view: AnyView(page.view().environment(workspace)),
                                width: size.width, height: size.height, scheme: scheme))
                    }
                }
            }
            for sheet in sheets {
                for scheme in [ColorScheme.light, .dark] {
                    jobs.append(
                        RenderJob(name: "\(sheet.name)-\(scheme.label)", view: AnyView(sheet.view().environment(workspace)), scheme: scheme)
                    )
                }
            }
            for (name, png) in try await renderOffscreen(jobs) {
                try png.write(to: folder.appending(path: "\(name).png"))
            }
        }
    }

    typealias Screen = (name: String, view: () -> AnyView)

    struct Batch {
        var setup: () -> Void = {}
        var pages: [Screen] = []
        var sheets: [Screen] = []
    }

    func batches(_ workspace: Workspace) -> [Batch] {
        var plain = Batch(
            pages: ScreenCatalog.entries(workspace).map { name, entry in
                (name, { AnyView(ScreenView(workspace: workspace, entry: entry)) })
            })
        plain.sheets = FormSnapshots.forms(workspace).map { name, view in ("form-\(name)", { view }) }
        plain.sheets += MathSyntax.allCases.map { syntax in
            ("input-guide-\(syntax.rawValue)", { AnyView(InputGuideSheet(workspace: workspace, syntax: syntax)) })
        }
        let columns = ScreenCatalog.columns(workspace)
        let hidden = ColumnPrefs(collapsed: Set(ColumnKind.allCases))
        var batches = [
            plain,
            Batch(
                pages: columns.map { name, entry in
                    (
                        "column-hidden-\(name)",
                        { AnyView(ScreenView(workspace: workspace, entry: entry).environment(\.columnPrefs, hidden)) }
                    )
                }),
        ]
        batches.append(
            Batch(
                pages: FirstRunStep.allCases.map { step in
                    ("first-run-\(step.rawValue)", { AnyView(FirstRunView(workspace: workspace, step: step)) })
                }))
        for (name, query) in [("search-empty", ""), ("search", "매칭")] {
            batches.append(
                Batch(
                    setup: { SnapshotDriver.shared.searchQuery = query },
                    sheets: [(name, { AnyView(SearchPalette(workspace: workspace, close: {}, choose: { _, _ in })) })]))
        }
        return batches
    }
}

@MainActor enum ScreenCatalog {
    static func entries(_ workspace: Workspace) -> [(name: String, entry: Navigator.Entry)] {
        var entries: [(String, Navigator.Entry)] = [
            ("today", Navigator.Entry(link: .place(.today))),
            ("grades", Navigator.Entry(link: .place(.grades))),
            ("requirements", Navigator.Entry(link: .place(.requirements))),
            ("people", Navigator.Entry(link: .place(.people))),
            ("codes", Navigator.Entry(link: .place(.codes))),
            ("whats-new", Navigator.Entry(link: .place(.whatsNew))),
            ("proposals", Navigator.Entry(link: .place(.proposals))),
        ]
        entries += SettingsTab.allCases.map { ("settings-\($0)", Navigator.Entry(link: .settings($0.page))) }
        if let semester = workspace.currentSemester {
            entries.append(("semester", Navigator.Entry(link: AppLink(.semester, semester.id))))
        }
        let now = workspace.now
        let live = workspace.currentCourses.first { c in
            let model = SessionsModel(workspace: workspace, courseId: c.id)
            return c.file.sessions.contains { s in
                model.isOngoing(
                    s,
                    end: s.expectedEnd(
                        schedule: c.file.course.schedule, classMinutes: workspace.settings.classMinutes, calendar: workspace.calendar),
                    now: now)
            }
        }
        if let course = live ?? workspace.currentCourses.max(by: { $0.file.sessions.count < $1.file.sessions.count }) {
            for section in CourseSection.allCases {
                entries.append(("course-\(section)", Navigator.Entry(link: .course(course.id, page: section.page), course: course.id)))
            }
            if let unit = UnitTree.outline(course.file.units).first?.unit {
                entries.append(("course-units-detail", Navigator.Entry(link: AppLink(.unit, unit.id), course: course.id)))
            }
        }
        if let split = workspace.currentCourses.first(where: { c in c.file.lectureFiles.contains { c.file.isSplit($0.id) } }) {
            entries.append(
                ("lecture-sessions", Navigator.Entry(link: .course(split.id, page: CourseSection.sessions.page), course: split.id)))
            if let unit = split.file.units.first(where: { !$0.lecturePages.isEmpty }) {
                entries.append(("lecture-unit", Navigator.Entry(link: AppLink(.unit, unit.id), course: split.id)))
            }
        }
        if let held = workspace.currentCourses.first(where: { !$0.file.recordings.isEmpty }), let recording = held.file.recordings.first {
            entries.append(
                ("course-recording", Navigator.Entry(link: AppLink(.recording, recording.id, anchor: .time(1700)), course: held.id)))
        }
        return entries
    }

    static func columns(_ workspace: Workspace) -> [(name: String, entry: Navigator.Entry)] {
        var entries: [(String, Navigator.Entry)] = [("settings", Navigator.Entry(link: .settings(SettingsTab.general.page)))]
        if let person = workspace.catalog.people.first { entries.append(("person", Navigator.Entry(link: AppLink(.person, person.id)))) }
        if let course = workspace.currentCourses.first {
            entries.append(("course", Navigator.Entry(link: .course(course.id), course: course.id)))
            entries.append(("course-notes", Navigator.Entry(link: .course(course.id, page: CourseSection.notes.page), course: course.id)))
            entries.append(
                ("course-quiz", Navigator.Entry(link: .course(course.id, page: CourseSection.quizSolve.page), course: course.id)))
        }
        return entries
    }
}

private extension ColorScheme {
    var label: String { self == .dark ? "dark" : "light" }
}

struct RenderJob {
    var name: String
    var view: AnyView
    var width: CGFloat?
    var height: CGFloat?
    var scheme: ColorScheme
}

// `ImageRenderer`는 AppKit 기반 컨트롤(텍스트 필드, 메뉴)을 그리지 못하고 `.task`를 실행하지 않는다. 그래서 각 뷰를 모든 디스플레이 밖의 창에 넣고 `cacheDisplay`로
// 그린다. batch의 창을 함께 열어 한 번에 기다리게 하는데, 이 기다림이 렌더 시간의 대부분이다.
@MainActor
func renderOffscreen(_ jobs: [RenderJob]) async throws -> [(String, Data)] {
    try await withOffscreenWindows(jobs) { open in
        try open.map { job, host in
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            return (job.name, try #require(rep.representation(using: .png, properties: [:])))
        }
    }
}

@MainActor
func measureOffscreen(_ jobs: [RenderJob]) async throws -> [CGFloat] {
    try await withOffscreenWindows(jobs) { open in open.map { $0.1.bounds.width } }
}

@MainActor
private func withOffscreenWindows<T>(_ jobs: [RenderJob], _ body: ([(RenderJob, NSView)]) throws -> T) async throws -> T {
    let open = jobs.map { job in
        let host = NSHostingView(rootView: job.view.environment(\.colorScheme, job.scheme))
        let fitting = host.fittingSize
        let size = CGSize(width: job.width ?? fitting.width, height: job.height ?? (job.width == nil ? fitting.height : 900))
        // SwiftUI는 화면에 있는 뷰에만 `.task`를 실행하므로, 완전히 투명한 창을 화면 밖 먼 곳에 두고 order in만 한다.
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: job.scheme == .dark ? .darkAqua : .aqua)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = host
        window.orderFrontRegardless()
        return (job, window, host)
    }

    defer {
        open.forEach {
            $0.1.contentView = nil; $0.1.close()
        }
    }
    try await settle()

    // 페이지는 스크롤되므로, 창을 main scroll view가 숨긴 만큼 키워 전체를 그린다. 늦게 불러오는 내용(공부 차트)은 첫 확장 뒤에 페이지를 늘리므로, 숨은 부분이 없을 때까지 되풀이한다.
    for _ in 0..<4 {
        var grew = false
        for (job, window, host) in open where job.width != nil && job.height == nil {
            guard let scroll = host.largestScrollView, let content = scroll.documentView else { continue }
            let hidden = content.frame.height - scroll.contentView.bounds.height
            if hidden > 1 {
                window.setContentSize(CGSize(width: window.frame.width, height: window.frame.height + hidden))
                grew = true
            }
        }
        guard grew else { break }
        try await settle()
    }

    // 내용이 자리 잡은 뒤에 job의 폭으로 되돌린다. 창은 매 순간 뷰의 최소 크기에 맞춰 커지고(데이터를 불러오기 전의 첫 배치도 포함한다), 저절로 줄어들지 않는다.
    var narrowed = false
    for (job, window, _) in open {
        if let width = job.width, window.frame.width > width {
            window.setContentSize(CGSize(width: width, height: window.frame.height))
            narrowed = true
        }
    }
    if narrowed { try await settle() }
    return try body(open.map { job, _, host in (job, host as NSView) })
}

// nested run loop가 아니라 sleep을 쓴다. run loop는 이 테스트가 main actor를 잡은 채로 돌기 때문에, main actor에서 재개하는 `.task`(공부 차트 불러오기)는
// 그리기가 끝난 뒤까지 기다린다.
private func settle() async throws {
    try await Task.sleep(for: .milliseconds(400))
}

private extension NSView {
    var largestScrollView: NSScrollView? {
        var all: [NSScrollView] = []
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView { all.append(s) }
            v.subviews.forEach(walk)
        }
        walk(self)
        return all.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
