import FolioActions
import FolioDomain
import SwiftUI

@MainActor
struct ProblemMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let set: ProblemSet
    let problem: Problem
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    var commands: [ProblemMenuCommand] { ProblemMenuCommand.commands(hasPage: set.materialId != nil) }

    func row(_ command: ProblemMenuCommand) -> MenuRow {
        switch command {
        case .openPage:
            MenuRow(
                command, .problemSetOpenSheet, "doc.richtext",
                .action {
                    if let id = set.materialId {
                        openLink(AppLink(.material, id, anchor: problem.page.map(AppLink.Anchor.page)), course: courseId)
                    }
                })
        case .solve:
            MenuRow(
                command, .unitsSolve, "pencil.and.list.clipboard",
                .action {
                    sheets.present(.solve(SolveRequest(course: courseId, set: set.id, problems: [problem.id])))
                })
        case .edit:
            .edit(command) { sheets.present(.problem(course: courseId, set: set.id, problem: problem.id)) }
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(ProblemRemove(course: courseId, set: set.id, problem: problem.id))) }
        }
    }
}
