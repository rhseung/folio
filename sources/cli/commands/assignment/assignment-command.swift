import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct AssignmentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assignment", abstract: String(localized: .assignmentAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.assignment)
}
