import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// Moving a note into a new folder of Notes/. The sheet shows where the note lands, ` 2` included, and that the folder
/// is made; that is the approval, so moving runs `note mv` without asking again, as the rename sheet does.
@MainActor @Observable
final class NoteFolderModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let note: NoteFile
    var name = ""
    private let moves: MoveUndo?

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, moves: MoveUndo? = nil) {
        self.workspace = workspace
        initial = course
        self.note = note
        self.moves = moves
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var folder: String { name.trimmingCharacters(in: .whitespaces) }
    var problem: StandardLayout.NoteFolderProblem? { StandardLayout.noteFolderProblem(name) }

    /// With the name `note mv` will give, ` 2` included.
    var target: String? {
        guard problem == nil else { return nil }
        let store = course.store
        return store.movedNoteURL(note, to: folder + "/" + note.url.lastPathComponent, in: course.file).flatMap { store.notesPath(of: $0) }
    }

    var isHere: Bool { target != nil && target == course.store.notesPath(of: note.url) }
    var canSave: Bool { target != nil && !isHere }

    var message: String {
        switch problem {
        case .empty: return String(localized: .notesFolderEmpty)
        case .nested: return String(localized: .notesFolderNested)
        case .reserved: return String(localized: .notesFolderReserved)
        case .hidden: return String(localized: .notesFolderHidden)
        case nil: break
        }
        guard let target, !isHere else { return String(localized: .notesFolderHere) }
        let path = CourseFolder.notes.rawValue + "/" + target
        // A folder already there (in any case: the volume ignores it) takes the note as it is.
        let exists = course.store.noteFolders().contains { $0.caseInsensitiveCompare(folder) == .orderedSame }
        return exists
            ? String(localized: .notesFolderInto(path))
            : String(localized: .notesFolderMakes(path, CourseFolder.notes.rawValue + "/" + folder))
    }

    func move() -> Bool {
        guard canSave, let target, let path = course.store.coursePath(of: note.url) else { return false }
        let ran = workspace.run(NoteMove(course: course.id, note: path, to: target))
        moves?.keep(ran)
        return ran != nil
    }
}
