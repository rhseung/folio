import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// Renaming a note in its folder. The sheet shows the file name the note will get, ` 2` included, before it is saved;
/// that is the approval, so saving runs `note mv` without asking again.
@MainActor @Observable
final class NoteRenameModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let note: NoteFile
    var name: String

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        self.workspace = workspace
        initial = course
        self.note = note
        name = note.title
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    /// Notes-relative, the way `note mv` takes it, with the name `note mv` will give.
    var target: String? {
        // A slash would move the note into a folder; renaming keeps it where it is.
        let typed = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        guard !typed.isEmpty else { return nil }
        let folder = NoteListModel.folder(of: note, in: course.store)
        let path = (folder.isEmpty ? "" : folder + "/") + typed + "." + note.format.fileExtension
        return course.store.movedNoteURL(note, to: path, in: course.file).flatMap { NoteListModel.notesPath(of: $0, in: course.store) }
    }

    var canSave: Bool { target.map { $0 != NoteListModel.notesPath(of: note.url, in: course.store) } ?? false }

    var message: String {
        guard let target, canSave else { return String(localized: .notesRenameEmpty) }
        return String(localized: .notesRenameTo(CourseFolder.notes.rawValue + "/" + target))
    }

    func rename() -> Bool {
        guard canSave, let target, let path = course.store.coursePath(of: note.url) else { return false }
        return workspace.run(NoteMove(course: course.id, note: path, to: target)) != nil
    }
}
