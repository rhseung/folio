import AppKit
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
        // The test host shares the app's bundle id and so its defaults: the user's last settings tab is put back.
        let savedTab = UserDefaults.standard.string(forKey: SettingsTab.storageKey)
        defer { UserDefaults.standard.set(savedTab, forKey: SettingsTab.storageKey) }

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

    /// Screens that can be on screen together. Course sections, settings tabs and the search query are app-wide state the
    /// views follow while they're open, so each value gets a batch of its own.
    struct Batch {
        var setup: () -> Void = {}
        var pages: [Screen] = []
        var sheets: [Screen] = []
    }

    func batches(_ workspace: Workspace) -> [Batch] {
        var plain = Batch(pages: [
            ("today", { AnyView(TodayView(workspace: workspace)) }),
            ("grades", { AnyView(GradesView(workspace: workspace)) }),
            ("requirements", { AnyView(RequirementsView(workspace: workspace) { _ in }) }),
            ("people", { AnyView(PeopleView(workspace: workspace) { _ in }) }),
            ("codes", { AnyView(CodesView(workspace: workspace)) }),
        ])
        if let semester = workspace.currentSemester {
            plain.pages.append(("semester", { AnyView(SemesterView(workspace: workspace, semesterID: semester.id) { _ in }) }))
        }
        plain.sheets = FormSnapshots.forms(workspace).map { name, view in ("form-\(name)", { view }) }
        var batches = [plain]

        if let course = workspace.currentCourses.max(by: { $0.file.sessions.count < $1.file.sessions.count }) {
            let page = { AnyView(CourseView(workspace: workspace, courseID: course.id)) }
            for section in CourseSection.allCases {
                batches.append(Batch(setup: { SnapshotDriver.shared.section = section; SnapshotDriver.shared.unitStep = nil },
                                     pages: [("course-\(section)", page)]))
            }
            batches.append(Batch(setup: { SnapshotDriver.shared.section = .units; SnapshotDriver.shared.unitStep = "detail" },
                                 pages: [("course-units-detail", page)]))
        }
        for tab in SettingsTab.allCases {
            batches.append(Batch(setup: { UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey) },
                                 pages: [("settings-\(tab)", { AnyView(SettingsView(workspace: workspace)) })]))
        }
        for (name, query) in [("search-empty", ""), ("search", "매칭")] {
            batches.append(Batch(setup: { SnapshotDriver.shared.searchQuery = query },
                                 sheets: [(name, { AnyView(SearchPalette(workspace: workspace, close: {}, choose: { _ in })) })]))
        }
        return batches
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
    return try open.map { job, _, host in
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return (job.name, try #require(rep.representation(using: .png, properties: [:])))
    }
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
