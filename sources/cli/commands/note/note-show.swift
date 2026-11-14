import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteShowAbstract), discussion: String(localized: .noteShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteShowHelpNote), valueName: "note"), completion: Complete.notes) var note:
            String = ""

        struct Body: Encodable {
            var id: UUID?
            var path: String
            var text: String
            var hash: String
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, n, path) = try r.notePath(note)
            let text = try c.store.read(n)
            if g.json { return try printJSON(Body(id: n.meta.id, path: path, text: text, hash: contentHash(text))) }
            say(text)
        }
    }
}
