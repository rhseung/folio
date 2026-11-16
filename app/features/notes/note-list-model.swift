import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class NoteListModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    private(set) var notes: [NoteFile] = []
    private(set) var folders: [String] = []
    var filter: NoteKind?
    var adding = false
    var pending: PendingAction?
    let moves: MoveUndo

    init(workspace: Workspace, course: LoadedCourse, moves: MoveUndo = MoveUndo()) {
        self.workspace = workspace
        initial = course
        self.moves = moves
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var notesRevision: Int { workspace.notesRevision }

    struct Row: Identifiable {
        let note: NoteFile
        let detail: String?
        var id: URL { note.url }
    }

    struct Part: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    var shown: [NoteFile] { notes.filter { filter == nil || $0.meta.kind == filter } }
    var parts: [Part] { Self.parts(shown, file: course.file, calendar: workspace.calendar) }

    var filterOptions: [(NoteKind?, String)] {
        [(NoteKind?.none, String(localized: .notesFilterAll))] + NoteKind.allCases.map { (Optional($0), $0.label) }
    }
    var addHelp: String { filter.map { String(localized: .notesNewKind($0.label)) } ?? String(localized: .notesNewFree) }
    var emptyLine: String { filter.map { String(localized: .notesKindEmpty($0.label)) } ?? String(localized: .notesEmpty) }

    static func parts(_ notes: [NoteFile], file: CourseFile, calendar: Calendar) -> [Part] {
        NoteGroup.grouped(notes, meta: \.meta, title: \.title, in: file).map { group, notes in
            Part(title: group.title, rows: notes.map { Row(note: $0, detail: detail(of: $0, in: group, file: file, calendar: calendar)) })
        }
    }

    private static func detail(of note: NoteFile, in group: NoteGroup, file: CourseFile, calendar: Calendar) -> String? {
        guard note.meta.id != nil else { return String(localized: .notesNeedsId) }

        let meta = note.meta
        switch group {
        case .classes:
            let sessions = file.sessions(pointingAt: meta.id)
            let covered =
                sessions.count > 1
                ? file.sessionSpan(of: meta.id, calendar: calendar)
                : sessions.first.map { $0.date.formatted(.dateTime.month().day().weekday()) }
            return covered.map { "\($0) · \(meta.kind.label)" } ?? "\(meta.kind.label) · " + String(localized: .notesNoSession)
        case .exams:
            return file.exams.first { $0.id == meta.examId }?.title ?? String(localized: .notesNoExam)
        case .units:
            return file.units(of: meta).map(\.title).joined(separator: ", ").nilIfEmpty ?? String(localized: .notesNoUnits)
        case .free:
            return meta.tags.isEmpty ? nil : meta.tags.map { "#" + $0 }.joined(separator: " ")
        }
    }

    func reload() {
        notes = (try? course.store.notes()) ?? []
        folders = course.store.noteFolders()
    }

    func open(_ note: NoteFile) -> UUID? {
        if let id = note.meta.id { return id }
        guard let id = workspace.noteId(of: note, in: course) else { return nil }
        reload()
        return id
    }

    func undoMove() {
        pending = moves.undo(workspace, course: course.id) { [weak self] in self?.reload() }
    }
}
