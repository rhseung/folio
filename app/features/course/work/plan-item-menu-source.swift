import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

@MainActor
struct PlanItemMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let examId: UUID
    let item: UUID
    let done: Bool
    let toggle: () -> Void
    let sheets: ItemSheetsAction

    var commands: [PlanItemMenuCommand] { ExamPlanItem.commands(done: done) }

    func row(_ command: PlanItemMenuCommand) -> MenuRow {
        switch command {
        case .done(let on):
            MenuRow(command, .menuDone, "checkmark.circle", .check(on) { _ in toggle() })
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(ExamPlanRemove(course: courseId, exam: examId, item: item))) }
        }
    }
}
