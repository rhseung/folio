import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "card", abstract: String(localized: .cardAbstract),
        subcommands: subcommandTypes)
}
