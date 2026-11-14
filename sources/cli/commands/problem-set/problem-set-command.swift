import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct ProblemSetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "problem-set", abstract: String(localized: .problemSetAbstract),
        subcommands: [List.self, Add.self, Record.self] + GeneratedCommands.problemSet)
}
