import FolioActions
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
        // What the scenario lacks is made here, so every link names something real and has to be found.
        if course.file.materials.isEmpty { workspace.run(MaterialTrack(course: course.id)) }
        let unit = try #require(course.file.units.first?.id ?? workspace.run(UnitAdd(course: course.id, title: "매칭"))?.made)
        let card = QuizCard(device: workspace.device, at: .now, unitId: unit, type: .free, category: .definition, prompt: "p", answer: "a")
        workspace.run(QuizCardSave(course: course.id, cards: [card]))
        workspace.run(ProblemSetSave(course: course.id, set: ProblemSet(device: workspace.device, at: .now, title: "Exercise 1", problems: [.init(number: "1")])))
        if course.file.recordings.isEmpty {
            // Recording is the recorder's, not an action's, so its entry is written here.
            let recording = Recording(device: workspace.device, at: .now, sessionId: course.file.sessions.first?.id, file: "Recordings/a.m4a")
            try ActionContext(gist: try #require(workspace.gist), device: workspace.device).edit(course.id) { $0.recordings.append(recording) }
            workspace.reload()
        }
        let file = try #require(workspace.course(course.id)?.file)
        func first(_ kind: AppLink.Kind, _ ids: [UUID]) throws -> AppLink { AppLink(kind, try #require(ids.first, "no \(kind) to link")) }
        for kind in AppLink.Kind.allCases {
            // No default: a new kind fails here too until the test gives it something to point at.
            let link: AppLink
            switch kind {
            case .today, .grades, .requirements, .people, .codes, .settings: link = .place(kind)
            case .semester: link = AppLink(.semester, try #require(workspace.currentSemester).id)
            case .course: link = .course(course.id)
            case .session: link = try first(.session, file.sessions.map(\.id))
            case .unit: link = try first(.unit, file.units.map(\.id))
            case .note: link = try first(.note, file.notes.map(\.id))
            case .material: link = try first(.material, file.materials.map(\.id))
            case .assignment: link = try first(.assignment, file.assignments.map(\.id))
            case .exam: link = try first(.exam, file.exams.map(\.id))
            case .problemSet: link = try first(.problemSet, file.problemSets.map(\.id))
            case .card: link = AppLink(.card, card.id)
            case .person: link = AppLink(.person, try #require(workspace.catalog.people.first).id)
            case .recording: link = try first(.recording, file.recordings.map(\.id))
            }
            let entry = try #require(workspace.entry(for: link), "\(kind): \(link) is found nowhere")
            let inCourse = kind.home == .course || kind.home == .quiz
            #expect(entry.course == (inCourse ? course.id : nil), "\(kind)")
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
