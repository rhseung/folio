import FolioDomain
import SwiftUI

@MainActor
struct RequirementMenuSource: ItemMenuSource {
    let show: @MainActor () -> Void
    let edit: @MainActor () -> Void
    let remove: @MainActor () -> Void

    var commands: [RequirementMenuCommand] { RequirementMenuCommand.commands }

    func row(_ command: RequirementMenuCommand) -> MenuRow {
        switch command {
        case .showCourses: MenuRow(command, .requirementsShowCourses, "list.bullet", .action(show))
        case .edit: MenuRow(command, .requirementsEditEllipsis, "pencil", .action(edit))
        case .remove: MenuRow(command, .requirementsRemoveEllipsis, "trash", role: .destructive, .action(remove))
        }
    }
}
