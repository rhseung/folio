import AppKit
import FolioDomain
import FolioFixtures
import SwiftUI
import Testing
@testable import Folio

/// Every page and sheet for every scenario, light and dark, as PNGs in FOLIO_RENDER_DIR (mise run render). Skipped
/// without it, so `mise run test-app` stays quick.
@MainActor @Suite(.serialized)
struct ScreenRenders {
    nonisolated static let env = ProcessInfo.processInfo.environment
    nonisolated static let folder = env["FOLIO_RENDER_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    /// `1180` is a width with the page at full height; `1440x900` also crops to that height, like a window would.
    static let sizes: [(name: String, width: CGFloat, height: CGFloat?)] = list("FOLIO_RENDER_SIZES", or: "1180,720").compactMap { spec in
        let parts = spec.split(separator: "x").compactMap { Double($0) }
        guard let width = parts.first else { return nil }
        return (spec, width, parts.count > 1 ? parts[1] : nil)
    }
    /// Name prefixes, e.g. `today,course-sessions,form-`.
    static let screens = list("FOLIO_RENDER_SCREENS", or: "")

    nonisolated static func list(_ key: String, or fallback: String) -> [String] {
        (env[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    nonisolated static let scenarios = Scenario.allCases.filter { s in list("FOLIO_RENDER_SCENARIOS", or: "").isEmpty || list("FOLIO_RENDER_SCENARIOS", or: "").contains(s.rawValue) }

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
                        jobs.append(RenderJob(name: "\(page.name)-\(size.name)-\(scheme.label)", view: AnyView(page.view().environment(workspace)),
                                              width: size.width, height: size.height, scheme: scheme))
                    }
                }
            }
            // Sheets and panels are drawn at their own size, as they open over the window.
            for sheet in sheets {
                for scheme in [ColorScheme.light, .dark] {
                    jobs.append(RenderJob(name: "\(sheet.name)-\(scheme.label)", view: AnyView(sheet.view().environment(workspace)), scheme: scheme))
                }
            }
            for (name, png) in try await renderOffscreen(jobs) {
                try png.write(to: folder.appending(path: "\(name).png"))
            }
        }
    }

    typealias Screen = (name: String, view: () -> AnyView)

    /// Screens that can be on screen together. The search query is app-wide state the palette follows while it's open,
    /// so each value gets a batch of its own.
    struct Batch {
        var setup: () -> Void = {}
        var pages: [Screen] = []
        var sheets: [Screen] = []
    }

    func batches(_ workspace: Workspace) -> [Batch] {
        // Each page is drawn from its link, as a window draws it, so a course page needs no app-wide switch to show.
        var plain = Batch(pages: ScreenCatalog.entries(workspace).map { name, entry in
            (name, { AnyView(ScreenView(workspace: workspace, entry: entry)) })
        })
        plain.sheets = FormSnapshots.forms(workspace).map { name, view in ("form-\(name)", { view }) }
        plain.sheets += MathSyntax.allCases.map { syntax in
            ("input-guide-\(syntax.rawValue)", { AnyView(InputGuideSheet(workspace: workspace, syntax: syntax)) })
        }
        // The list columns hidden by hand where they would fit (#62). Open over the page they need the glass this render
        // cannot draw, so the window snapshot (`FOLIO_SNAPSHOT_COLUMN=open`) shows that.
        let columns = ScreenCatalog.columns(workspace)
        let hidden = ColumnPrefs(collapsed: Set(ColumnKind.allCases))
        var batches = [plain, Batch(pages: columns.map { name, entry in
            ("column-hidden-\(name)", { AnyView(ScreenView(workspace: workspace, entry: entry).environment(\.columnPrefs, hidden)) })
        })]
        for (name, query) in [("search-empty", ""), ("search", "매칭")] {
            batches.append(Batch(setup: { SnapshotDriver.shared.searchQuery = query },
                                 sheets: [(name, { AnyView(SearchPalette(workspace: workspace, close: {}, choose: { _, _ in })) })]))
        }
        return batches
    }
}

/// A link for every screen, at one that gives it something to show: the places, the current term, and each page of
/// the course in class at the scenario's moment (so the sessions page shows a class under way; else the busiest),
/// with its first unit open.
@MainActor enum ScreenCatalog {
    static func entries(_ workspace: Workspace) -> [(name: String, entry: Navigator.Entry)] {
        var entries: [(String, Navigator.Entry)] = [
            ("today", Navigator.Entry(link: .place(.today))),
            ("grades", Navigator.Entry(link: .place(.grades))),
            ("requirements", Navigator.Entry(link: .place(.requirements))),
            ("people", Navigator.Entry(link: .place(.people))),
            ("codes", Navigator.Entry(link: .place(.codes))),
            ("whats-new", Navigator.Entry(link: .place(.whatsNew))),
        ]
        entries += SettingsTab.allCases.map { ("settings-\($0)", Navigator.Entry(link: .settings($0.page))) }
        if let semester = workspace.currentSemester {
            entries.append(("semester", Navigator.Entry(link: AppLink(.semester, semester.id))))
        }
        let now = workspace.now
        let live = workspace.currentCourses.first { c in
            let model = SessionsModel(workspace: workspace, courseId: c.id)
            return c.file.sessions.contains { s in
                model.isOngoing(s, end: s.expectedEnd(schedule: c.file.course.schedule, classMinutes: workspace.settings.classMinutes, calendar: workspace.calendar), now: now)
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
        // A course whose units split its slides (#321): its classes and a split unit draw the section strip.
        if let split = workspace.currentCourses.first(where: { c in c.file.lectureFiles.contains { c.file.isSplit($0.id) } }) {
            entries.append(("lecture-sessions", Navigator.Entry(link: .course(split.id, page: CourseSection.sessions.page), course: split.id)))
            if let unit = split.file.units.first(where: { !$0.lecturePages.isEmpty }) {
                entries.append(("lecture-unit", Navigator.Entry(link: AppLink(.unit, unit.id), course: split.id)))
            }
        }
        // Opened at a moment past the start, as a link from a note or a tab let go of does.
        if let held = workspace.currentCourses.first(where: { !$0.file.recordings.isEmpty }), let recording = held.file.recordings.first {
            entries.append(("course-recording", Navigator.Entry(link: AppLink(.recording, recording.id, anchor: .time(1700)), course: held.id)))
        }
        return entries
    }

    /// A screen of each list column (#62), at a page each has beside it.
    static func columns(_ workspace: Workspace) -> [(name: String, entry: Navigator.Entry)] {
        var entries: [(String, Navigator.Entry)] = [("settings", Navigator.Entry(link: .settings(SettingsTab.general.page)))]
        if let person = workspace.catalog.people.first { entries.append(("person", Navigator.Entry(link: AppLink(.person, person.id)))) }
        if let course = workspace.currentCourses.first {
            entries.append(("course", Navigator.Entry(link: .course(course.id), course: course.id)))
            entries.append(("course-notes", Navigator.Entry(link: .course(course.id, page: CourseSection.notes.page), course: course.id)))
            entries.append(("course-quiz", Navigator.Entry(link: .course(course.id, page: CourseSection.quizSolve.page), course: course.id)))
        }
        return entries
    }
}

private extension ColorScheme {
    var label: String { self == .dark ? "dark" : "light" }
}

/// Without a width the view takes its own fitting size; without a height the page grows to its scrolled content.
struct RenderJob {
    var name: String
    var view: AnyView
    var width: CGFloat?
    var height: CGFloat?
    var scheme: ColorScheme
}

/// `ImageRenderer` can't draw AppKit-backed controls (text fields, menus) and never runs `.task`, which loads the study
/// chart and more, so each view goes in a window off every display and is drawn with `cacheDisplay`. The windows of a
/// batch are open together so they settle in one wait, which is most of the time a render takes.
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

/// The width each job's view was drawn at. A screen whose rows or columns won't shrink to the job's width grows its
/// hosting view past it, as it would push a window or a pane out.
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
        // Fully transparent and far off screen: ordered in only because SwiftUI runs `.task` for views on screen.
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: job.scheme == .dark ? .darkAqua : .aqua)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = host
        window.orderFrontRegardless()
        return (job, window, host)
    }
    // Detached, not only closed: a view left alive keeps following the app-wide state the next batches set, and the
    // main actor slows with every one of them.
    defer { open.forEach { $0.1.contentView = nil; $0.1.close() } }
    try await settle()
    // Pages scroll, so a window grows by what its main scroll view hides to draw all of it. Content that loads late (the
    // study chart) lengthens the page after the first grow, so it repeats until nothing is hidden.
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
    // Back to the job's width, once the content has settled: a window grows to fit its view's minimum at every
    // moment, a first pass before its data loaded included, and doesn't shrink back by itself.
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

/// Lets layout, `.task` and `onGeometryChange` settle before drawing. A sleep, not a nested run loop: the loop would run
/// while this test still holds the main actor, so a `.task` resuming on it (the study chart's load) waits until after the draw.
private func settle() async throws {
    try await Task.sleep(for: .milliseconds(400))
}

private extension NSView {
    /// The page's own scroll view, not a list or text field inside it.
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
