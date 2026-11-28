import FolioAI
import FolioDomain
import SwiftUI

struct CourseView: View {
    @State private var model: CourseModel
    @Environment(\.paneInsert) private var paneInsert
    @Environment(\.place) private var place
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace, courseID: UUID) {
        _model = State(initialValue: CourseModel(workspace: workspace, courseId: courseID))
    }

    var body: some View {
        if let course = model.course {
            let workspace = model.workspace
            Group {
                // 노트의 카드 칸과 풀기는 과목 열 없이 칸 전체를 쓴다. 옆 칸의 노트나 문제지와 자리를 나눠야 하기 때문이다.
                if model.place.kind == .noteCards, let note = model.place.id {
                    NoteCardsView(workspace: workspace, course: course, noteId: note).id(note)
                } else if model.section == .solve, let query = model.place.solve {
                    SolveScreen(workspace: workspace, request: SolveRequest(course: course.id, query: query))
                        .id(query)
                } else {
                    sections(course, workspace: workspace)
                }
            }
            // 열이 아니라 화면 전체에 단다. 열을 접거나 풀기 화면이 열을 가려도 칸 마디의 아이콘은 여전히 구역을 따라야 한다.
            .crumb(model.section.title, level: 1, symbol: model.section.tab.symbol)
            .courseAccent(model.accent)
            .navigationTitle(course.title)
            .navigationSubtitle(model.section.title)
            .studyTime(course: model.courseId)
            .onChange(of: place, initial: true) { _, entry in if let entry { model.follow(entry) } }
            .onChange(of: model.place) { _, link in openLink(link, course: model.courseId) }
            .onChange(of: paneInsert?.text) { _, text in
                guard let text else { return }
                model.noteInsert = text
                paneInsert?.text = nil
            }
        } else {
            ContentUnavailableView(String(localized: .courseNotFound), systemImage: "questionmark.folder")
        }
    }

    func sections(_ course: LoadedCourse, workspace: Workspace) -> some View {
        ColumnSplit(kind: .courseSections) {
            CourseColumn(model: model, course: course)
        } content: {
            Group {
                switch model.section {
                case .overview: CourseOverview(model: model, course: course)
                case .sessions:
                    if let recording = model.openRecording {
                        RecordingPage(
                            workspace: workspace, course: course, recording: recording, place: model.place, moved: model.moved
                        )
                        .id(recording.id)
                    } else {
                        SessionsView(workspace: workspace, course: course)
                    }
                case .units:
                    UnitsView(workspace: workspace, course: course, place: model.place) { id in
                        model.openUnit = id
                        model.moved(id.map { AppLink(.unit, $0) })
                    }
                case .notes: CourseNotesPage(model: model, course: course)
                case .problems: ProblemsView(workspace: workspace, course: course)
                case .cards: CardsView(workspace: workspace, course: course)
                case .materials: MaterialsView(workspace: workspace, course: course, place: model.place, moved: model.moved)
                case .assignments: AssignmentsView(workspace: workspace, course: course)
                case .grades: CourseGradesView(workspace: workspace, course: course)
                case .exams: ExamsView(workspace: workspace, course: course)
                case .solve: EmptyView()
                }
            }
            .environment(\.linkFocus, model.focus)
            .paperList()
        }
    }
}

@MainActor
extension LoadedCourse {
    func codeLine(_ workspace: Workspace) -> String {
        let c = file.course
        let prefix = c.codes.first.flatMap { id in workspace.catalog.codes.first { $0.id == id }?.prefix } ?? ""
        return prefix + c.number
    }

    func factChips(_ workspace: Workspace) -> [String] {
        let c = file.course
        let professors = c.instructorIds.compactMap { id in workspace.catalog.people.first { $0.id == id }?.name }
        return [String(localized: .courseCredits(c.credits.formatted())), c.gradingMode.label] + professors
    }
}

extension GradingMode {
    var label: String {
        switch self {
        case .relative: String(localized: .gradingModeRelative)
        case .absolute: String(localized: .gradingModeAbsolute)
        case .passFail: "S/U"
        }
    }
}
