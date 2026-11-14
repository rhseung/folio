import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct MaterialCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "material", abstract: String(localized: .materialAbstract),
        subcommands: [List.self, Show.self, Read.self, Link.self, Relink.self, Import.self, Write.self, Split.self]
            + GeneratedCommands.material)

}
