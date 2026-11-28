import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

// 계획의 줄 하나의 메뉴다. 줄의 ⋯ 단추와 오른쪽 클릭이 같은 메뉴를 연다. 어떤 행이 서는지는 `PlanRow.commands`가 정한다.
@MainActor
struct PlanRowMenuSource: ItemMenuSource {
    let model: PlanModel
    let row: PlanRow

    var commands: [PlanItemMenuCommand] { row.commands(today: model.today) }

    func row(_ command: PlanItemMenuCommand) -> MenuRow {
        switch command {
        case .advance:
            MenuRow(command, .planMenuAdvance, "arrow.up", .action { model.advance(row) })
        case .postpone:
            MenuRow(
                command, model.postponesToTomorrow(row) ? .planMenuPostponeTomorrow : .planMenuPostponeNext, "goforward",
                disabled: !model.canPostpone(row), .action { model.postpone(row) })
        case .pickDay:
            MenuRow(
                command, .planMenuPickDay, "calendar",
                .submenu(
                    model.moveDays(row).map { day in
                        MenuRow.Leaf(id: day, title: model.dayLabel(day), symbol: "calendar") { model.move(row, to: day) }
                    }))
        case .done(let on):
            // 단계가 여럿이면 단계마다 따로 체크한다. 정독만 끝낸 날이 있기 때문이다.
            if row.steps.count > 1 {
                MenuRow(
                    command, .menuDone, "checkmark.circle",
                    .submenu(
                        row.steps.map { step in
                            MenuRow.Leaf(id: step.item, title: model.label(step, in: row), symbol: "checkmark.circle", checked: step.isDone)
                            {
                                model.toggle(step, in: row)
                            }
                        }))
            } else {
                MenuRow(command, .menuDone, "checkmark.circle", .check(on) { model.setDone(row.steps.map(\.item), $0, in: row) })
            }
        case .remove:
            MenuRow(command, .planMenuRemove, "xmark", role: .destructive, .action { model.remove(row) })
        }
    }
}
