import FolioActions
import FolioDomain
import SwiftUI

@MainActor
struct CardMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let card: QuizCard
    var solveWrong: (() -> Void)?
    let sheets: ItemSheetsAction

    var commands: [CardMenuCommand] { CardMenuCommand.commands(solvesWrong: solveWrong != nil) }

    func row(_ command: CardMenuCommand) -> MenuRow {
        switch command {
        case .solveWrong:
            MenuRow(command, .quizStatsSolveUnitWrong, "arrow.counterclockwise", .action { solveWrong?() })
        case .edit:
            .edit(command) { sheets.present(.card(course: courseId, draft: CardDraft(card))) }
        case .share:
            .share(command, AppLink(.card, card.id), course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(QuizCardRemove(course: courseId, unit: card.unitId, card: card.id))) }
        }
    }
}
