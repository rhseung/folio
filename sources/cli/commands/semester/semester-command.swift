import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct SemesterCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "semester", abstract: String(localized: .semesterAbstract),
        subcommands: subcommandTypes)
}
