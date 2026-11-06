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

    @Test func everyScreenFitsTheWidthItIsGiven() async throws {
        let workspace = try Workspace.scenario(.busyDay)
        var screens = ScreenCatalog.entries(workspace)
        // Folded, the people list and a person are drawn one at a time, so each is checked.
        let person = try #require(workspace.catalog.people.first)
        screens.append(("person", Navigator.Entry(link: AppLink(.person, person.id))))
        for (name, width, drawn) in try await measure(screens, workspace) {
            #expect(drawn <= width + 0.5, "\(name) at \(Int(width)) is \(drawn) wide")
        }
    }

    func measure(_ screens: [(name: String, entry: Navigator.Entry)], _ workspace: Workspace) async throws -> [(String, CGFloat, CGFloat)] {
        let jobs = screens.flatMap { name, entry in
            Self.widths.map { width in
                // A page beside a column clips what it can't fit rather than push the window out; lifted here, so an
                // overflowing page grows the window this measures.
                let screen = ScreenView(workspace: workspace, entry: entry).environment(workspace).environment(\.revealsOverflow, true)
                return RenderJob(name: name, view: AnyView(screen), width: width, height: nil, scheme: .light)
            }
        }
        let drawn = try await measureOffscreen(jobs)
        return zip(jobs, drawn).map { job, drawn in (job.name, job.width ?? 0, drawn) }
    }
}
