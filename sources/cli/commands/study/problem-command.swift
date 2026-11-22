import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct ProblemCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "problem", abstract: String(localized: .problemAbstract),
        subcommands: subcommandTypes)
}
