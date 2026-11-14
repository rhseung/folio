import FolioAI
import FolioDomain
import SwiftUI

struct CourseView: View {
    @State private var model: CourseModel
    @State private var pageReset = 0
    @Environment(\.paneInsert) private var paneInsert
    @Environment(\.place) private var place
    @Environment(\.openLink) private var openLink
    @Environment(\.paneFocused) private var paneFocused

    init(workspace: Workspace, courseID: UUID) {
        _model = State(initialValue: CourseModel(workspace: workspace, courseId: courseID))
    }

    var body: some View {
        if let course = model.course {
            let workspace = model.workspace
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
                    // 퀴즈 페이지를 옮겨 다녀도 퀴즈 모델과 대기 중인 풀기 요청이 남도록, 모든 퀴즈 페이지를 한 갈래로
                    // 둔다.
                    case .quizSolve, .quizCards, .quizStats, .quizProblems:
                        QuizView(workspace: model.workspace, course: course, section: $model.section)
                    case .materials: MaterialsView(workspace: workspace, course: course, place: model.place, moved: model.moved)
                    case .assignments: AssignmentsView(workspace: workspace, course: course)
                    case .grades: CourseGradesView(workspace: workspace, course: course)
                    case .exams: ExamsView(workspace: workspace, course: course)
                    }
                }
                .environment(\.linkFocus, model.focus)
                // identity를 새로 주면 페이지가 연 파일이나 단원이 닫힌다. 구역 crumb이 바라는 동작은 그것뿐이다.
                .id(pageReset)
                .paperList()
            }
            // 열이 아니라 split에 단다. 접으면 열은 사라지지만 구역은 여전히 위치 표시의 맨 앞에 있어야 한다.
            .crumb(model.section.title, level: 1, symbol: model.section.tab.symbol) {
                model.resetPage()
                pageReset += 1
            }
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
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.section, initial: true) { _, new in if let new, paneFocused { model.section = new } }
            #endif
        } else {
            ContentUnavailableView(String(localized: .courseNotFound), systemImage: "questionmark.folder")
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
