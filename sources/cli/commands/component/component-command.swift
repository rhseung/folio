import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct ComponentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "component", abstract: String(localized: .componentAbstract),
        subcommands: [List.self] + GeneratedCommands.component + [Move.self])
}
