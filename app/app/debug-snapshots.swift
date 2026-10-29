#if DEBUG && os(macOS)
import AppKit
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
    /// A step to linger on, so the real window (toolbar and all, which cacheDisplay leaves out) can be screen-captured.
    static let holdStep = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_HOLD"]
    /// A narrower window (e.g. `1100`) to catch labels that wrap or truncate once the columns squeeze.
    static let width = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_WIDTH"].flatMap(Double.init) ?? 1440

    var section: CourseSection?
    /// Inside the units section: `detail` opens the first unit, `review` also opens its review sheet.
    var unitStep: String?
    /// Opens the Claude inspector on course screens. `cacheDisplay` can't draw inspectors, so no capture step uses it yet.
    var claudePanel = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_CLAUDE"] != nil
    /// Extra screens drawn outside the main window (the forms), run just before quitting.
    @ObservationIgnored var extraCaptures: ((URL) async -> Void)?
    var editCourse = false
    var editExam = false
    var openPDF = false
    var searchQuery: String?

    func run(select: (Destination) -> Void, courses: [UUID], semester: UUID?) async {
        guard let directory = Self.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: Self.width, height: 900))
            // On screen for the hold step's capture; a restored frame can leave it off every display.
            window.center()
        }

        var plan: [(String, Destination, CourseSection?)] = [("today", .today, nil), ("grades", .grades, nil), ("requirements", .requirements, nil), ("people", .people, nil), ("codes", .codes, nil)]
        if let semester { plan.append(("semester", .semester(semester), nil)) }
        if let first = courses.first {
            plan += CourseSection.allCases.map { ("course-\($0)", .course(first), $0) }
        }
        for (name, destination, section) in plan {
            select(destination)
            self.section = section
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: directory.appending(path: "\(name).png"))
            if name == Self.webStep { await captureWebViews(to: directory, name: name) }
            if name == Self.holdStep { try? await Task.sleep(for: .seconds(6)) }
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
            openPDF = true
            try? await Task.sleep(for: .seconds(2.5))
            capture(to: directory.appending(path: "course-materials-pdf.png"))
            if Self.holdStep == "course-materials-pdf" { try? await Task.sleep(for: .seconds(6)) }
            openPDF = false
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
        for tab in SettingsTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
            select(.settings)
            try? await Task.sleep(for: .seconds(1.2))
            capture(to: directory.appending(path: "settings-\(tab).png"))
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

    func capture(to url: URL) {
        let window = NSApp.windows.first { $0.isVisible && $0.sheetParent == nil }
        // The main window's frame view, so the toolbar row is in the picture too; a sheet is its content alone.
        guard let view = window?.attachedSheet?.contentView ?? window?.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
