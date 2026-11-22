import FolioActions
import FolioDomain
import SwiftUI

@MainActor
struct CardMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let card: StudyCard
    let sheets: ItemSheetsAction

    var commands: [CardMenuCommand] { CardMenuCommand.all }

    func row(_ command: CardMenuCommand) -> MenuRow {
        switch command {
        case .flip:
            MenuRow(
                command, .unitsFlip, "rectangle.on.rectangle", .action { sheets.present(.flipCards(course: courseId, unit: card.unitId)) })
        case .edit:
            .edit(command) { sheets.present(.card(course: courseId, draft: CardDraft(card))) }
        case .share:
            .share(command, AppLink(.card, card.id), course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(CardRemove(course: courseId, unit: card.unitId, card: card.id))) }
        }
    }
}
