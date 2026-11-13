import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CourseStore {
    /// Notes-relative, as `note mv` and the folder menu name places: "" for Notes/ itself.
    func notesPath(of url: URL) -> String? {
        let prefix = CourseFolder.notes.rawValue + "/"
        return coursePath(of: url).flatMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
    }

    func noteFolder(of note: NoteFile) -> String {
        ((notesPath(of: note.url) ?? "") as NSString).deletingLastPathComponent
    }

    func noteMoveTargets(for note: NoteFile) -> [String] {
        let here = noteFolder(of: note)
        return noteFolders().filter { $0 != here }
    }

    static func noteFolderLabel(_ folder: String) -> String {
        folder.isEmpty ? CourseFolder.notes.rawValue : CourseFolder.notes.rawValue + "/" + folder
    }
}

extension LoadedCourse {
    /// The note as course.json has it now. A `NoteFile` is read once, and the bar's link menu, the Claude panel or the
    /// CLI may have linked it since: writing its old links back would undo theirs.
    func stored(_ note: NoteFile) -> NoteFile? {
        store.note(at: store.notePath(of: note.url), in: file)
    }
}

extension NoteLink {
    init(course: UUID, note: UUID, meta: NoteMeta) {
        self.init(course: course, note: note, kind: meta.kind, session: meta.sessionId, exam: meta.examId, units: meta.unitIds, math: meta.math)
    }
}

extension Workspace {
    /// Asks with the name the note will have there, ` 2` included, since that is what the user approves.
    func askMove(_ note: NoteFile, into folder: String, course: LoadedCourse,
                 then done: @escaping @MainActor (ActionContext) -> Void) -> PendingAction? {
        let store = course.store
        let path = (folder.isEmpty ? "" : folder + "/") + note.url.lastPathComponent
        guard let source = store.coursePath(of: note.url), let url = store.movedNoteURL(note, to: path, in: course.file),
              let target = store.notesPath(of: url) else { return nil }
        return ask(NoteMove(course: course.id, note: source, to: target), then: done)
    }

    /// One moved in from an old folder has no ID until it is adopted, which every way of opening it does first.
    func noteId(of note: NoteFile, in course: LoadedCourse) -> UUID? {
        if let id = note.meta.id { return id }
        guard let path = course.store.coursePath(of: note.url) else { return nil }
        return run(NoteAdopt(course: course.id, note: path))?.made
    }
}
