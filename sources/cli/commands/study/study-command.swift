import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct StudyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "study", abstract: String(localized: .studyAbstract),
        subcommands: subcommandTypes)
}
