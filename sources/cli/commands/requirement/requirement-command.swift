import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct RequirementCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "requirement", abstract: String(localized: .requirementAbstract),
        subcommands: subcommandTypes)
}
