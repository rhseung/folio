import FolioDomain
import SwiftUI

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
