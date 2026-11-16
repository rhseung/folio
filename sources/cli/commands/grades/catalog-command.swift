import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CatalogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "catalog", abstract: String(localized: .catalogAbstract), subcommands: subcommandTypes)
}
