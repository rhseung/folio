import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class NoteEditModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let note: NoteFile
    var name: String
    var folder: String
    var math: MathSyntax
    private let moves: MoveUndo?

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, moves: MoveUndo? = nil) {
        self.workspace = workspace
        initial = course
        self.note = note
        self.moves = moves
        name = note.title
        folder = course.store.noteFolder(of: note)
        math = note.meta.math
        // 넘겨받은 과목은 노트 항목보다 오래되었을 수 있다. `meta`처럼 읽지 않으면 시트가 이미 바뀐 상태로 열린다.
        math = meta.math
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    private var meta: NoteMeta { (course.stored(note) ?? note).meta }

    var folders: [String] {
        let all = course.store.noteFolders()
        return all.contains(folder) ? all : [folder] + all
    }

    var folderOptions: [(String, String)] { folders.map { ($0, CourseStore.noteFolderLabel($0)) } }

    var choosesMath: Bool { note.format == .markdown && note.meta.id != nil }

    private var targetURL: URL? {
        let typed = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        guard !typed.isEmpty else { return nil }
        let path = (folder.isEmpty ? "" : folder + "/") + typed + "." + note.format.fileExtension
        return course.store.movedNoteURL(note, to: path, in: course.file)
    }

    var target: String? { targetURL.flatMap { course.store.notesPath(of: $0) } }

    var relocates: Bool { target.map { $0 != course.store.notesPath(of: note.url) } ?? false }
    var changesMath: Bool { choosesMath && math != meta.math }

    var canSave: Bool { target != nil && (relocates || changesMath) }

    var message: String? {
        guard let target else { return String(localized: .notesRenameEmpty) }
        guard relocates else { return changesMath ? nil : String(localized: .notesRenameEmpty) }
        return String(localized: .notesRenameTo(CourseFolder.notes.rawValue + "/" + target))
    }

    var pdf: BuiltPDFMove? { relocates ? targetURL.flatMap { course.store.builtPDFMove(of: note, to: $0, in: course.file) } : nil }

    var pdfName: String? { pdf.map { $0.blocked ? $0.from : $0.to } }
    var pdfDetail: String? {
        pdf.map { $0.blocked ? String(localized: .notesRenamePdfStays($0.to)) : String(localized: .notesRenamePdfFollows($0.from)) }
    }

    // 문법은 노트 ID로 저장되고 옮겨도 ID는 그대로이므로 먼저 쓴다.
    func apply() -> Bool {
        guard canSave, let target, let path = course.store.coursePath(of: note.url) else { return false }
        if changesMath, let id = note.meta.id {
            var now = meta
            now.math = math
            guard workspace.run(NoteLink(course: course.id, note: id, meta: now)) != nil else { return false }
        }
        guard relocates else { return true }
        let ran = workspace.run(NoteMove(course: course.id, note: path, to: target))
        moves?.keep(ran)
        return ran != nil
    }
}
