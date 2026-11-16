import FolioDomain
import SwiftUI

@MainActor
struct ComponentMenuSource: ItemMenuSource {
    let model: CourseGradesModel
    let component: GradeComponent
    let addsScore: Bool
    let index: Int
    let count: Int

    var commands: [ComponentMenuCommand] { ComponentMenuCommand.commands(addsScore: addsScore, index: index, count: count) }

    func row(_ command: ComponentMenuCommand) -> MenuRow {
        switch command {
        case .addScore: MenuRow(command, .courseGradesAddScoreEllipsis, "plus", .action { model.addScore(component) })
        case .edit: .edit(command) { model.editingComponent = component }
        case .moveUp: MenuRow(command, .courseGradesMoveUp, "arrow.up", .action { model.move(component.id, by: -1) })
        case .moveDown: MenuRow(command, .courseGradesMoveDown, "arrow.down", .action { model.move(component.id, by: 1) })
        case .remove: .remove(command) { model.remove(component) }
        }
    }
}
