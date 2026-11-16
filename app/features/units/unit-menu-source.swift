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

    private var dueToday: Bool {
        workspace.reviewStates(of: courseId, now: workspace.liveNow)[unit.id]?.isDue(on: workspace.today) ?? false
    }

    var commands: [UnitMenuCommand] {
        workspace.course(courseId)?.file.commands(for: unit, host: host, dueToday: dueToday) ?? []
    }

    func row(_ command: UnitMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(link, course: courseId) }
        case .review:
            MenuRow(command, .unitsStartReview, "play", .action { sheets.present(.review(course: courseId, unit: unit.id)) })
        case .skipToday:
            MenuRow(command, .todayReviewsSkip, "forward", .action { sheets.confirm(workspace.skipReviews([(courseId, unit.id)])) })
        case .addCard:
            MenuRow(
                command, .menuAddCard, "rectangle.stack.badge.plus",
                .submenu([
                    MenuRow.Leaf(id: "manual", title: String(localized: .quizCardsAddManual), symbol: "square.and.pencil") {
                        sheets.present(.card(course: courseId, draft: CardDraft(unitId: unit.id)))
                    },
                    MenuRow.Leaf(id: "claude", title: String(localized: .quizCardsAddClaude), symbol: "sparkles") {
                        sheets.present(.generateCards(course: courseId, unit: unit.id))
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
