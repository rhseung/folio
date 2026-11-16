import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct UnitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unit", abstract: String(localized: .unitAbstract),
        subcommands: subcommandTypes)
}
