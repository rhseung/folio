import FolioActions
import FolioDomain
import SwiftUI

/// A unit's menu, the same in the units list, on the unit's page, the course overview, Today's reviews and search (#403).
@MainActor
struct UnitMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let unit: FolioDomain.Unit
    let host: MenuHost
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var link: AppLink { AppLink(.unit, unit.id) }

    /// Due on the study day or overdue, as Today lists it.
    private var dueToday: Bool {
        guard let due = workspace.reviewStates(of: courseId, now: workspace.liveNow)[unit.id]?.due else { return false }
        return due.days(until: workspace.today) >= 0
    }

    var commands: [UnitCommand] {
        workspace.course(courseId)?.file.commands(for: unit, host: host, dueToday: dueToday) ?? []
    }

    func row(_ command: UnitCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(link, course: courseId) }
        case .review:
            MenuRow(command, .unitsStartReview, "play", .action { sheets.present(.review(course: courseId, unit: unit.id)) })
        case .skipToday:
            MenuRow(command, .todayReviewsSkip, "forward", .action { sheets.confirm(workspace.skipReviews([(courseId, unit.id)])) })
        case .addCard:
            MenuRow(command, .menuAddCard, "rectangle.stack.badge.plus", .submenu([
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

/// For `.contextMenu` and the unit page's `⋯`.
struct UnitMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let unitId: UUID
    var host: MenuHost = .elsewhere

    var body: some View {
        if let unit = workspace.course(courseId)?.file.units.first(where: { $0.id == unitId }) {
            ItemMenu(source: UnitMenuSource(workspace: workspace, courseId: courseId, unit: unit, host: host, openLink: openLink, sheets: sheets))
        }
    }
}
