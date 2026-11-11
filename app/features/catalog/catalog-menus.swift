import FolioDomain
import SwiftUI

/// A person's menu in the people list (#403). Their page is their editor; deleting asks on that page.
@MainActor
struct PersonMenuSource: ItemMenuSource {
    let person: Person
    let host: MenuHost
    let mail: URL?
    let remove: @MainActor () -> Void
    let openLink: OpenLinkAction
    let openURL: OpenURLAction

    var commands: [PersonMenuCommand] { PersonMenuCommand.commands(host: host, hasMail: mail != nil) }

    func row(_ command: PersonMenuCommand) -> MenuRow {
        switch command {
        case .open: .open(command) { openLink(AppLink(.person, person.id)) }
        case .mail: MenuRow(command, .peopleMail, "envelope", .action { if let mail { openURL(mail) } })
        case .share: .share(command, AppLink(.person, person.id), course: nil)
        case .remove: .remove(command, remove)
        }
    }
}

/// A code's tile menu. Editing is the tile's popover; a code a course still uses can't go.
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

/// A requirement category's menu, on its figure.
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
