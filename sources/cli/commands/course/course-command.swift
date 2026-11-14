import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CourseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "course", abstract: String(localized: .courseAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.course + [Set.self])
}
