import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Widget: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteWidgetAbstract),
            subcommands: subcommandTypes)
    }
}
