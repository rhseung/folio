import FolioDomain
import FolioFixtures
import SwiftUI
import Testing
@testable import Folio

/// The screen contract (#43): every screen draws its link in the width it is given, a full window, a pane or an
/// iPhone, folding rather than running past the side or clipping its rows.
@MainActor @Suite(.serialized)
struct ScreenFitTests {
    /// An iPhone, a pane of a split window, a full window.
    static let widths: [CGFloat] = [390, 720, 1440]

    @Test func everyKindOfLinkHasAScreen() throws {
        let workspace = try Workspace.scenario(.busyDay)
        let course = try #require(workspace.currentCourses.first)
        let files = workspace.courses.map(\.file)
        // What the scenario lacks is linked by a made-up ID, found in no course: the entry then names the course.
        func first(_ kind: AppLink.Kind, _ ids: (CourseFile) -> [UUID]) -> AppLink { AppLink(kind, files.lazy.flatMap(ids).first ?? UUID()) }
        for kind in AppLink.Kind.allCases {
            // No default: a new kind fails here too until the test gives it something to point at.
            let link: AppLink = switch kind {
            case .today, .grades, .requirements, .people, .codes, .settings: .place(kind)
            case .semester: AppLink(.semester, try #require(workspace.currentSemester).id)
            case .course: .course(course.id)
            case .session: first(.session) { $0.sessions.map(\.id) }
            case .unit: first(.unit) { $0.units.map(\.id) }
            case .note: first(.note) { $0.notes.map(\.id) }
            case .material: first(.material) { $0.materials.map(\.id) }
            case .assignment: first(.assignment) { $0.assignments.map(\.id) }
            case .exam: first(.exam) { $0.exams.map(\.id) }
            case .problemSet: AppLink(.problemSet, UUID())
            case .card: AppLink(.card, UUID())
            case .person: AppLink(.person, try #require(workspace.catalog.people.first).id)
            }
            let entry = workspace.entry(for: link) ?? Navigator.Entry(link: link, course: course.id)
            #expect(Screen(entry) != .missing, "\(kind) has no screen")
            #expect(Screen(entry).link != nil)
        }
        #expect(Screen(Navigator.Entry(link: AppLink(.exam, UUID()))) == .missing)
    }

    /// Screens not folded yet, and the width they still need: the people and settings pages have a list column beside
    /// the page with no narrow form yet (how it folds is still to decide, #43), and the catalog editor's table is wider
    /// than a pane. A course's column doesn't push the window out (its page may shrink to nothing, so AppKit can't loop
    /// on constraints), so this check can't see a course page clip; renders at 390 show it.
    static let unfolded: [(name: String, below: CGFloat)] = [("people", 720), ("settings-", 720), ("settings-catalog", 1440)]

    @Test func everyScreenFitsTheWidthItIsGiven() async throws {
        let workspace = try Workspace.scenario(.busyDay)
        let screens = ScreenCatalog.entries(workspace).filter { $0.name != "settings" }
        var drawn = try await measure(screens, workspace)
        // The settings page shows the tab last chosen, kept app-wide, so each tab is drawn on its own.
        let savedTab = UserDefaults.standard.string(forKey: SettingsTab.storageKey)
        defer { UserDefaults.standard.set(savedTab, forKey: SettingsTab.storageKey) }
        for tab in SettingsTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
            drawn += try await measure([("settings-\(tab)", Navigator.Entry(link: .place(.settings)))], workspace)
        }
        for (name, width, drawn) in drawn {
            if Self.unfolded.contains(where: { name.hasPrefix($0.name) && width < $0.below }) {
                withKnownIssue { #expect(drawn <= width + 0.5, "\(name) at \(Int(width)) is \(drawn) wide") }
            } else {
                #expect(drawn <= width + 0.5, "\(name) at \(Int(width)) is \(drawn) wide")
            }
        }
    }

    func measure(_ screens: [(name: String, entry: Navigator.Entry)], _ workspace: Workspace) async throws -> [(String, CGFloat, CGFloat)] {
        let jobs = screens.flatMap { name, entry in
            Self.widths.map { width in
                RenderJob(name: name, view: AnyView(ScreenView(workspace: workspace, entry: entry).environment(workspace)), width: width, height: nil, scheme: .light)
            }
        }
        let drawn = try await measureOffscreen(jobs)
        return zip(jobs, drawn).map { job, drawn in (job.name, job.width ?? 0, drawn) }
    }
}
