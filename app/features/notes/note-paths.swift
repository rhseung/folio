import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CourseStore {
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
    // `NoteFile`은 한 번 읽은 값이다. 그 뒤 링크 메뉴, Claude 패널, CLI가 링크를 걸었을 수 있으므로, 예전 링크를 다시
    // 쓰면 그 변경을 지운다.
    func stored(_ note: NoteFile) -> NoteFile? {
        store.note(at: store.notePath(of: note.url), in: file)
    }
}

extension NoteLink {
    init(course: UUID, note: UUID, meta: NoteMeta) {
        self.init(
            course: course, note: note, kind: meta.kind, session: meta.sessionId, exam: meta.examId, units: meta.unitIds, math: meta.math)
    }
}

extension Workspace {
    func askMove(
        _ note: NoteFile, into folder: String, course: LoadedCourse,
        then done: @escaping @MainActor (ActionContext) -> Void
    ) -> PendingAction? {
        let store = course.store
        let path = (folder.isEmpty ? "" : folder + "/") + note.url.lastPathComponent
        guard let source = store.coursePath(of: note.url), let url = store.movedNoteURL(note, to: path, in: course.file),
            let target = store.notesPath(of: url)
        else { return nil }
        return ask(NoteMove(course: course.id, note: source, to: target), then: done)
    }

    func noteId(of note: NoteFile, in course: LoadedCourse) -> UUID? {
        if let id = note.meta.id { return id }
        guard let path = course.store.coursePath(of: note.url) else { return nil }
        return run(NoteAdopt(course: course.id, note: path))?.made
    }

    func noteId(titled title: String, in course: LoadedCourse) -> UUID? {
        ((try? course.store.notes()) ?? []).linked(title).flatMap { noteId(of: $0, in: course) }
    }
}
