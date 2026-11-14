import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

@MainActor
struct AssignmentMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let assignment: Assignment
    let host: MenuHost
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var link: AppLink { AppLink(.assignment, assignment.id) }
    private var folder: String { AssignmentFiles.path(of: assignment) }
    private var folderURL: URL? { workspace.course(courseId)?.store.fileURL(folder) }

    var commands: [AssignmentMenuCommand] {
        #if os(macOS)
        let revealable = folderURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        #else
        let revealable = false
        #endif
        return workspace.course(courseId)?.file.commands(for: assignment, host: host, revealable: revealable) ?? []
    }

    func row(_ command: AssignmentMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(link, course: courseId) }
        case .addFiles:
            MenuRow(
                command, .menuAddFilesEllipsis, "doc.badge.plus", .action { sheets.addFiles(FileIntake(course: courseId, folder: folder)) })
        case .status(let current):
            MenuRow(
                command, .assignmentsStatus, current.symbol,
                .submenu(
                    AssignmentStatus.menuOrder.map { status in
                        MenuRow.Leaf(id: status, title: status.label, symbol: status.symbol, checked: status == current) { set(status) }
                    }))
        case .edit:
            .edit(command) { sheets.present(.assignment(course: courseId, assignment: assignment.id)) }
        case .share:
            .share(command, link, course: courseId)
        case .showInFinder:
            MenuRow(command, .commonShowInFinder, "folder", .action { if let folderURL { revealInFinder(folderURL) } })
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(AssignmentRemove(course: courseId, assignment: assignment.id))) }
        }
    }

    func set(_ status: AssignmentStatus) {
        workspace.run(AssignmentStatusSet(course: courseId, assignment: assignment.id, status: status))
    }
}
