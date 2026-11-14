import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class NewNoteModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    var title = ""
    var format = NoteFormat.markdown
    var kind: NoteKind {
        didSet {
            guard kind != oldValue else { return }
            // 선택기는 더는 나열하지 않는 회차에는 아무것도 보이지 않는다. 이 ID를 두면 이미 이 종류의 노트가 있는
            // 회차를 연결해 그 노트에서 연결을 빼앗는다.
            if let sessionId, !sessionOptions.contains(where: { $0.id == sessionId }) { self.sessionId = nil }
            suggestTitle()
        }
    }
    var sessionId: UUID? {
        didSet { suggestTitle() }
    }
    var examId: UUID?
    var unitIds: [UUID] = []
    private var suggested = ""

    init(workspace: Workspace, course: LoadedCourse, kind: NoteKind) {
        self.workspace = workspace
        initial = course
        self.kind = kind
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    var canAdd: Bool { !trimmedTitle.isEmpty }

    enum Link { case session, exam, units, none }

    var link: Link {
        switch kind {
        case .rough, .review: .session
        case .examSummary: .exam
        case .unit: .units
        case .free: .none
        }
    }

    var kindOptions: [(NoteKind, String)] { NoteKind.allCases.map { ($0, $0.label) } }
    var formatOptions: [(NoteFormat, String)] { NoteFormat.allCases.map { ($0, $0.label) } }

    var sessionOptions: [PickOption<UUID?>] {
        let sessions = course.file.sessions.filter { [kind] in !$0.isCancelled && $0.note(of: kind) == nil }.sorted { $0.date > $1.date }
        return [PickOption(id: nil, title: String(localized: .commonNone))]
            + sessions.map { PickOption(id: $0.id, title: course.file.title(of: $0, calendar: workspace.calendar)) }
    }

    var examOptions: [PickOption<UUID?>] {
        let exams = course.file.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        return [PickOption(id: nil, title: String(localized: .commonNone))] + exams.map { PickOption(id: $0.id, title: $0.title) }
    }

    var unitOptions: [PickOption<UUID>] {
        UnitTree.outline(course.file.units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) }
    }
    func unitSubtree(_ id: UUID) -> Set<UUID> { UnitTree.subtree(of: id, in: course.file.units) }

    private func suggestTitle() {
        guard title == suggested else { return }
        let session = link == .session ? course.file.sessions.first { $0.id == sessionId } : nil
        suggested = session.map { course.file.noteTitle(for: $0, kind: kind, calendar: workspace.calendar) } ?? ""
        title = suggested
    }

    func add() -> UUID? {
        guard canAdd else { return nil }
        let action = NoteAdd(
            course: course.id, title: trimmedTitle, kind: kind, format: format,
            session: link == .session ? sessionId : nil, exam: link == .exam ? examId : nil, units: link == .units ? unitIds : [])
        return workspace.run(action)?.made
    }
}

extension NoteFormat {
    var label: String {
        switch self {
        case .markdown: String(localized: .notesFormatMarkdown)
        case .tex: "LaTeX"
        }
    }
}
