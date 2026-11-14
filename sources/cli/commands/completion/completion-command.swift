import ArgumentParser
import FolioActions
import FolioStorage
import Foundation

struct CompletionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion", abstract: String(localized: .completionAbstract),
        discussion: String(localized: .completionDiscussion))

    @Argument(help: "zsh, bash, fish") var shell: String

    func run() throws {
        guard let s = CompletionShell(rawValue: shell) else {
            throw CLIError(exit: .usage, message: String(localized: .completionUnknownShell))
        }
        say(Folio.completionScript(for: s))
    }
}
