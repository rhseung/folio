import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteEditAbstract), discussion: String(localized: .noteEditDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpNote), valueName: "note"), completion: Complete.notes) var note: String =
            ""
        @Option(help: ArgumentHelp(String(localized: .noteEditHelpOld), valueName: "text")) var old: [String] = []
        @Option(help: ArgumentHelp(String(localized: .noteEditHelpNew), valueName: "text")) var new: [String] = []
        @Option(help: ArgumentHelp(String(localized: .noteEditHelpAppend), valueName: "text")) var append: String?

        func run() throws {
            guard old.count == new.count else {
                throw CLIError(exit: .usage, message: String(localized: .noteEditUnpaired(old.count, new.count)))
            }
            let ctx = try CLI.context(g)
            let (c, _, path) = try Resolver(ctx).notePath(note)
            let replacements = zip(old, new).map { NoteEdit.Replacement(old: $0, new: $1) }
            try perform(spec: NoteEdit(course: c.id, note: path, replacements: replacements, append: append), g, ctx: ctx)
        }
    }
}
