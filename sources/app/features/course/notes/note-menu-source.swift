import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

@MainActor
struct NoteMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let note: NoteFile
    let host: MenuHost
    var moves: MoveUndo?
    var open: (@MainActor () -> Void)?
    var build: (@MainActor () -> Void)?
    var canBuild = true
    var removed: (@MainActor () -> Void)?
    var save: (@MainActor () -> Void)?
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var course: LoadedCourse? { workspace.course(courseId) }

    private var builtPDF: UUID? {
        guard let course, let path = course.store.builtPDF(of: note, in: course.file) else { return nil }
        return course.file.materials.first { $0.path == path }?.id
    }

    private var reviewed: Session? {
        guard let id = note.meta.id else { return nil }
        return course?.file.sessions.filter { $0.reviewNoteId == id }.max { $0.date < $1.date }
    }

    var commands: [NoteMenuCommand] {
        #if os(macOS)
        let finder = true
        #else
        let finder = false
        #endif
        let review = reviewed.flatMap { course?.file.review(of: $0) }
        let all = NoteMenuCommand.commands(host: host, builtPDF: builtPDF != nil, builds: build != nil, review: review, finder: finder)
        return note.meta.id == nil ? all.filter { $0 != .share } : all
    }

    func row(_ command: NoteMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) {
                if let open { open() } else if let id = note.meta.id { openLink(AppLink(.note, id), course: courseId) }
            }
        case .openPDF:
            MenuRow(
                command, .materialsOpenPdf, "doc.richtext",
                .action { if let builtPDF { openLink(AppLink(.material, builtPDF), course: courseId) } })
        case .build:
            MenuRow(command, .textFileBuild, "hammer", disabled: !canBuild, .action { build?() })
        case .review(let review):
            MenuRow(
                command, .notesReviewDone, "checkmark.circle",
                .check(review.isChecked) { _ in
                    if let reviewed, let unfinished = review.toggled.reviewUnfinished {
                        workspace.setReviewNoteUnfinished(unfinished, of: reviewed.id, in: courseId)
                    }
                })
        case .edit:
            .edit(command) {
                save?()
                sheets.present(.note(NoteSheetRequest(course: courseId, note: note, moves: moves)))
            }
        case .move:
            MenuRow(command, .notesMoveTo, "folder", .submenu(moveLeaves))
        case .share:
            .share(command, AppLink(.note, note.meta.id ?? UUID()), course: courseId)
        case .showInFinder:
            .showInFinder(command, note.url)
        case .remove:
            .remove(command) {
                guard let path = course?.store.coursePath(of: note.url) else { return }
                sheets.confirm(workspace.ask(NoteRemove(course: courseId, note: path), button: .notesTrash) { _ in removed?() })
            }
        }
    }

    private var moveLeaves: [MenuRow.Leaf] {
        guard let course else { return [] }
        return course.store.noteMoveTargets(for: note).map { folder in
            MenuRow.Leaf(id: folder, title: CourseStore.noteFolderLabel(folder), symbol: "folder") {
                save?()
                sheets.confirm(workspace.askMove(note, into: folder, course: course) { [moves] ctx in moves?.keep(ctx) })
            }
        } + [
            MenuRow.Leaf(id: "new", title: String(localized: .notesFolderNewEllipsis), symbol: "folder.badge.plus") {
                save?()
                sheets.present(.noteFolder(NoteSheetRequest(course: courseId, note: note, moves: moves)))
            }
        ]
    }
}
