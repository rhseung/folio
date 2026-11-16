import FolioDomain
import SwiftUI

@MainActor
struct CodeMenuSource: ItemMenuSource {
    let edit: @MainActor () -> Void
    let remove: @MainActor () -> Void
    let removable: Bool

    var commands: [CodeMenuCommand] { CodeMenuCommand.commands }

    func row(_ command: CodeMenuCommand) -> MenuRow {
        switch command {
        case .edit: .edit(command, edit)
        case .remove: MenuRow(command, .commonDelete, "trash", role: .destructive, disabled: !removable, .action(remove))
        }
    }
}
