import FolioActions
import FolioDomain
import SwiftUI

@MainActor
struct UnitMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let unit: FolioDomain.Unit
    let host: MenuHost
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var link: AppLink { AppLink(.unit, unit.id) }

    var commands: [UnitMenuCommand] {
        workspace.course(courseId)?.file.commands(for: unit, host: host) ?? []
    }

    func row(_ command: UnitMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command, link: link, course: courseId) { openLink(link, course: courseId) }
        case .solve:
            MenuRow(
                command, .unitsSolve, "play",
                .action { sheets.present(.solve(SolveRequest(course: courseId, units: [unit.id], problems: []))) })
        case .done(let done):
            MenuRow(
                command, done ? .unitsDoneUndo : .unitsDone, done ? "arrow.uturn.backward" : "checkmark",
                .action { workspace.run(UnitDone(course: courseId, unit: unit.id, done: !done)) })
        case .addCard:
            MenuRow(
                command, .menuAddCard, "rectangle.stack.badge.plus",
                .submenu([
                    MenuRow.Leaf(id: "manual", title: String(localized: .cardsAddManual), symbol: "square.and.pencil") {
                        sheets.present(.card(course: courseId, draft: CardDraft(unitId: unit.id)))
                    },
                    MenuRow.Leaf(id: "claude", title: String(localized: .cardsAddClaude), symbol: "sparkles") {
                        sheets.present(.suggestCards(course: courseId, unit: unit.id))
                    },
                ]))
        case .moveUp:
            MenuRow(command, .unitsMoveUp, "arrow.up", .action { move(by: -1) })
        case .moveDown:
            MenuRow(command, .unitsMoveDown, "arrow.down", .action { move(by: 1) })
        case .share:
            .share(command, link, course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(UnitRemove(course: courseId, unit: unit.id))) }
        }
    }

    private func move(by offset: Int) {
        workspace.run(UnitMove(course: courseId, unit: unit.id, target: .by(offset)))
    }
}
