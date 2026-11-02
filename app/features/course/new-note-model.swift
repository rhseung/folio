import FolioActions
import FolioDomain
import Foundation
import Observation

/// The properties of a new note, asked for before the file exists, since neither format keeps them in the file.
@MainActor @Observable
final class NewNoteModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    var title = ""
    var format = NoteFormat.markdown
    var kind: NoteKind {
        didSet {
            guard kind != oldValue else { return }
            // The picker shows nothing for a session it no longer lists, so keeping the id would link a session that
            // already has this kind's note, taking it from that note.
            if let sessionId, !sessionOptions.contains(where: { $0.id == sessionId }) { self.sessionId = nil }
            suggestTitle()
        }
    }
    var sessionId: UUID? {
        didSet { suggestTitle() }
    }
    var examId: UUID?
    var unitIds: [UUID] = []
    /// The title last filled in from the session, replaced while the user hasn't typed their own.
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
        case .topic: .units
        case .free: .none
        }
    }

    var kindOptions: [(NoteKind, String)] { NoteKind.allCases.map { ($0, $0.label) } }
    var formatOptions: [(NoteFormat, String)] { NoteFormat.allCases.map { ($0, $0.label) } }

    /// Sessions that don't have this kind's note yet, newest first: a session holds one rough and one review note, and
    /// taking one that has it would leave the other note without its session.
    var sessionOptions: [PickOption<UUID?>] {
        let taken: (Session) -> Bool = { [kind] in (kind == .rough ? $0.roughNoteId : $0.reviewNoteId) != nil }
        let sessions = course.file.sessions.filter { !$0.isCancelled && !taken($0) }.sorted { $0.date > $1.date }
        return [PickOption(id: nil, title: String(localized: .commonNone))]
            + sessions.map { PickOption(id: $0.id, title: course.file.name(of: $0), detail: $0.topic.isEmpty ? nil : $0.topic) }
    }

    var examOptions: [PickOption<UUID?>] {
        let exams = course.file.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        return [PickOption(id: nil, title: String(localized: .commonNone))] + exams.map { PickOption(id: $0.id, title: $0.title.isEmpty ? $0.kind.label : $0.title) }
    }

    var unitOptions: [PickOption<UUID>] { UnitTree.outline(course.file.units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) } }
    func unitSubtree(_ id: UUID) -> Set<UUID> { UnitTree.subtree(of: id, in: course.file.units) }

    /// A session's note is named the way `session note` names it, until the user types a title of their own.
    private func suggestTitle() {
        guard title == suggested else { return }
        let session = link == .session ? course.file.sessions.first { $0.id == sessionId } : nil
        suggested = session.map { kind == .rough ? course.file.name(of: $0) : "\(course.file.name(of: $0)) 정리" } ?? ""
        title = suggested
    }

    func add() -> UUID? {
        guard canAdd else { return nil }
        let action = NoteAdd(course: course.id, title: trimmedTitle, kind: kind, format: format,
                             session: link == .session ? sessionId : nil, exam: link == .exam ? examId : nil, units: link == .units ? unitIds : [])
        guard let id = workspace.run(action)?.made else { return nil }
        workspace.notesRevision += 1
        return id
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
