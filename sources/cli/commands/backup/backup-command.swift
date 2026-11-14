import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct BackupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup", abstract: String(localized: .backupAbstract), subcommands: GeneratedCommands.backup + [List.self])

}
