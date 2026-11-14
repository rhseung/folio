import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct SettingsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings", abstract: String(localized: .settingsAbstract), subcommands: subcommandTypes)
}
