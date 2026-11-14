import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import UniformTypeIdentifiers

extension NoteGroup {
    var title: String {
        switch self {
        case .classes: String(localized: .notesPartClass)
        case .exams: String(localized: .notesPartExam)
        case .units: String(localized: .notesPartUnit)
        case .free: String(localized: .notesPartFree)
        }
    }
}

@MainActor @Observable
final class NotesModel {
    let workspace: Workspace
    private let initial: LoadedCourse

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    func note(_ id: UUID?) -> NoteFile? { id.flatMap { try? course.store.note(id: $0) } }
}
