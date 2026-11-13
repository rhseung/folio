import FolioActions
import FolioDomain
import FolioFixtures
import SwiftUI
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct ScreenFitTests {
    static let widths: [CGFloat] = [390, 720, 1440]

    @Test func everyKindOfLinkHasAScreen() throws {
        let workspace = try Workspace.scenario(.busyDay)
        let course = try #require(workspace.currentCourses.first)
        if course.file.materials.isEmpty { workspace.run(MaterialTrack(course: course.id)) }
        let unit = try #require(course.file.units.first?.id ?? workspace.run(UnitAdd(course: course.id, title: "매칭"))?.made)
        let card = QuizCard(device: workspace.device, at: .now, unitId: unit, type: .free, category: .definition, prompt: "p", answer: "a")
        workspace.run(QuizCardSave(course: course.id, cards: [card]))
        workspace.run(
            ProblemSetSave(
                course: course.id, set: ProblemSet(device: workspace.device, at: .now, title: "Exercise 1", problems: [.init(number: "1")]))
        )
        if course.file.recordings.isEmpty {
            let recording = Recording(
                device: workspace.device, at: .now, sessionId: course.file.sessions.first?.id, file: "Recordings/a.m4a")
            try ActionContext(gist: try #require(workspace.gist), device: workspace.device).edit(course.id) {
                $0.recordings.append(recording)
            }
            workspace.reload()
        }

        let file = try #require(workspace.course(course.id)?.file)
        func first(_ kind: AppLink.Kind, _ ids: [UUID]) throws -> AppLink { AppLink(kind, try #require(ids.first, "no \(kind) to link")) }
        for kind in AppLink.Kind.allCases {
            let link: AppLink
            switch kind {
            case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals: link = .place(kind)
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
        let person = try #require(workspace.catalog.people.first)
        screens.append(("person", Navigator.Entry(link: AppLink(.person, person.id))))
        for (name, width, drawn) in try await measure(screens, workspace) {
            #expect(drawn <= width + 0.5, "\(name) at \(Int(width)) is \(drawn) wide")
        }
    }

    func measure(_ screens: [(name: String, entry: Navigator.Entry)], _ workspace: Workspace) async throws -> [(String, CGFloat, CGFloat)] {
        let jobs = screens.flatMap { name, entry in
            Self.widths.map { width in
                // 열 옆의 페이지는 들어가지 않는 부분을 잘라 창을 밀어내지 않는다. 여기서는 그 제한을 풀어서, 넘치는 페이지가 측정하는 창을 키우게 한다.
                let screen = ScreenView(workspace: workspace, entry: entry).environment(workspace).environment(\.revealsOverflow, true)
                return RenderJob(name: name, view: AnyView(screen), width: width, height: nil, scheme: .light)
            }
        }
        let drawn = try await measureOffscreen(jobs)
        return zip(jobs, drawn).map { job, drawn in (job.name, job.width ?? 0, drawn) }
    }
}

extension ScreenFitTests {
    func draw(_ entry: Navigator.Entry, _ workspace: Workspace, width: CGFloat, collapsed: Set<ColumnKind> = []) async throws -> (
        width: CGFloat, labels: [String]
    ) {
        let seen = LabelBox()
        let screen = ScreenView(workspace: workspace, entry: entry)
            .environment(workspace)
            .environment(\.revealsOverflow, true)
            .environment(\.columnPrefs, ColumnPrefs(collapsed: collapsed))
            .onPreferenceChange(ColumnButtonLabels.self) { labels in MainActor.assumeIsolated { seen.labels = labels } }
        let drawn = try #require(
            try await measureOffscreen([RenderJob(name: "column", view: AnyView(screen), width: width, height: nil, scheme: .light)]).first)
        return (drawn, seen.labels)
    }

    @Test func aFoldedColumnLeavesItsButtonAndTheOverlayFits() async throws {
        let workspace = try Workspace.scenario(.busyDay)
        let course = try #require(workspace.currentCourses.first)
        let person = try #require(workspace.catalog.people.first)
        let sections = (show: String(localized: .designColumnShowSections), hide: String(localized: .designColumnHideSections))
        let list = (show: String(localized: .designColumnShowList), hide: String(localized: .designColumnHideList))
        let screens: [(Navigator.Entry, (show: String, hide: String))] = [
            (Navigator.Entry(link: .course(course.id), course: course.id), sections),
            (Navigator.Entry(link: .settings(SettingsTab.general.page)), sections),
            (Navigator.Entry(link: AppLink(.person, person.id)), list),
        ]
        defer { SnapshotDriver.shared.columnOpen = false }
        for (entry, label) in screens {
            for open in [false, true] {
                SnapshotDriver.shared.columnOpen = open
                let drawn = try await draw(entry, workspace, width: 390)
                #expect(drawn.width <= 390.5, "\(entry.link) at 390, open \(open), is \(drawn.width) wide")
                #expect(drawn.labels.contains(open ? label.hide : label.show), "\(entry.link) at 390, open \(open): \(drawn.labels)")
            }
        }

        SnapshotDriver.shared.columnOpen = false
        for (entry, label) in screens {
            let docked = try await draw(entry, workspace, width: 1440)
            #expect(docked.labels.contains(label.hide), "\(entry.link) docked: \(docked.labels)")
            let hidden = try await draw(entry, workspace, width: 1440, collapsed: Set(ColumnKind.allCases))
            #expect(hidden.labels.contains(label.show), "\(entry.link) hidden by hand: \(hidden.labels)")
            #expect(hidden.width <= 1440.5)
        }
    }

    @Test func aFoldedListWithNothingBesideIsThePageWithNoButton() async throws {
        let workspace = try Workspace.scenario(.busyDay)
        let drawn = try await draw(Navigator.Entry(link: .place(.people)), workspace, width: 390)
        #expect(drawn.width <= 390.5)
        #expect(!drawn.labels.contains(String(localized: .designColumnShowList)))
    }
}

@MainActor private final class LabelBox {
    var labels: [String] = []
}
