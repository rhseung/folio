import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension UnitCommand {
    struct Pages: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .unitPagesAbstract), subcommands: GeneratedCommands.unitPages)
    }
}
