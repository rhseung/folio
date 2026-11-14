import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct ExamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exam", abstract: String(localized: .examAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.exam + [Scope.self, Plan.self, PlanCheck.self])
}
