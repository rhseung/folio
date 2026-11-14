import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct NoteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note", abstract: String(localized: .noteAbstract),
        subcommands: subcommandTypes)

}
