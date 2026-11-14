import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

@MainActor
struct ExamMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let exam: Exam
    let host: MenuHost
    var summary: UUID?? = nil
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var link: AppLink { AppLink(.exam, exam.id) }

    var commands: [ExamMenuCommand] {
        workspace.course(courseId)?.file.commands(for: exam, host: host) ?? []
    }

    func row(_ command: ExamMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(link, course: courseId) }
        case .summary:
            MenuRow(command, hasSummary ? .examsSummaryOpen : .examsSummaryMake, "doc.text", .action(openSummary))
        case .addFiles:
            MenuRow(
                command, .menuAddFilesEllipsis, "doc.badge.plus",
                .action {
                    if let folder = MaterialIntake.folder(of: exam) { sheets.addFiles(FileIntake(course: courseId, folder: folder)) }
                })
        case .edit:
            .edit(command) { sheets.present(.exam(course: courseId, exam: exam.id)) }
        case .share:
            .share(command, link, course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(ExamRemove(course: courseId, exam: exam.id))) }
        }
    }

    private var hasSummary: Bool {
        if let summary { return summary != nil }
        return workspace.examSummary(of: exam.id, in: courseId) != nil
    }

    private func openSummary() {
        if let id = workspace.run(ExamSummary(course: courseId, exam: exam.id))?.made { openLink(AppLink(.note, id), course: courseId) }
    }
}
