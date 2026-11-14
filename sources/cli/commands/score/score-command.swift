import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct ScoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score", abstract: String(localized: .scoreAbstract),
        subcommands: [List.self] + GeneratedCommands.score)
}
