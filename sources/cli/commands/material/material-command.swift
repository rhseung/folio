import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct MaterialCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "material", abstract: String(localized: .materialAbstract),
        subcommands: subcommandTypes)

}
