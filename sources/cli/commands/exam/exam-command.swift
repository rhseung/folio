import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct ExamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exam", abstract: String(localized: .examAbstract),
        subcommands: subcommandTypes)
}
