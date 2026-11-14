import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct ReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review", abstract: String(localized: .reviewAbstract),
        subcommands: GeneratedCommands.review + [Skip.self])
}
