import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// A note's one sheet (#403): its name, its folder under Notes/ and, for markdown, its math syntax. The sheet shows the
/// path the note will get, ` 2` included, before it is saved; that is the approval, so saving runs `note mv` without
/// asking again. The note's kind and links stay in the bar's link menu, which writes as it is changed.
@MainActor @Observable
final class NoteEditModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let note: NoteFile
    var name: String
    /// Notes-relative: "" for Notes/ itself.
    var folder: String
    var math: MathSyntax
    private let moves: MoveUndo?

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, moves: MoveUndo? = nil) {
        self.workspace = workspace
        initial = course
        self.note = note
        self.moves = moves
        name = note.title
        folder = NoteListModel.folder(of: note, in: course.store)
        math = (course.store.note(at: course.store.notePath(of: note.url), in: course.file) ?? note).meta.math
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    /// From course.json as it is now: the bar's link menu, the Claude panel or the CLI may have linked the note since
    /// `note` was read, and writing the old links back with the syntax would undo that.
    private var meta: NoteMeta { (course.store.note(at: course.store.notePath(of: note.url), in: course.file) ?? note).meta }

    var folders: [String] {
        let all = course.store.noteFolders()
        return all.contains(folder) ? all : [folder] + all
    }

    /// The syntax is the markdown preview's; a `.tex` note is TeX throughout, and a note with no ID has no entry to keep it.
    var choosesMath: Bool { note.format == .markdown && note.meta.id != nil }

    private var targetURL: URL? {
        // A slash would move the note into a folder; the folder row is where that is chosen.
        let typed = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        guard !typed.isEmpty else { return nil }
        let path = (folder.isEmpty ? "" : folder + "/") + typed + "." + note.format.fileExtension
        return course.store.movedNoteURL(note, to: path, in: course.file)
    }

    /// Notes-relative, the way `note mv` takes it, with the name `note mv` will give.
    var target: String? { targetURL.flatMap { NoteListModel.notesPath(of: $0, in: course.store) } }

    var relocates: Bool { target.map { $0 != NoteListModel.notesPath(of: note.url, in: course.store) } ?? false }
    var changesMath: Bool { choosesMath && math != meta.math }

    var canSave: Bool { target != nil && (relocates || changesMath) }

    var message: String? {
        guard let target else { return String(localized: .notesRenameEmpty) }
        guard relocates else { return changesMath ? nil : String(localized: .notesRenameEmpty) }
        return String(localized: .notesRenameTo(CourseFolder.notes.rawValue + "/" + target))
    }

    /// The PDF a `.tex` note's build wrote, which `note mv` renames with it; shown so the sheet approves that too.
    var pdf: BuiltPDFMove? { relocates ? targetURL.flatMap { course.store.builtPDFMove(of: note, to: $0, in: course.file) } : nil }

    var pdfName: String? { pdf.map { $0.blocked ? $0.from : $0.to } }
    var pdfDetail: String? { pdf.map { $0.blocked ? String(localized: .notesRenamePdfStays($0.to)) : String(localized: .notesRenamePdfFollows($0.from)) } }

    /// The syntax first: it is kept by the note's ID, which a move leaves as it is.
    func apply() -> Bool {
        guard canSave, let target, let path = course.store.coursePath(of: note.url) else { return false }
        if changesMath, let id = note.meta.id {
            let now = meta
            guard workspace.run(NoteLink(course: course.id, note: id, kind: now.kind, session: now.sessionId, exam: now.examId,
                                         units: now.unitIds, math: math)) != nil else { return false }
        }
        guard relocates else { return true }
        let ran = workspace.run(NoteMove(course: course.id, note: path, to: target))
        moves?.keep(ran)
        return ran != nil
    }
}
