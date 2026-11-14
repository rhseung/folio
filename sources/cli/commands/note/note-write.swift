import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteWriteAbstract), discussion: String(localized: .noteWriteDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpNote), valueName: "note"), completion: Complete.notes) var note: String =
            ""
        @Option(help: ArgumentHelp(String(localized: .noteWriteHelpFile), valueName: "file"), completion: .file()) var file: String
        @Option(help: ArgumentHelp(String(localized: .noteWriteHelpExpect), valueName: "hash")) var expect: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let (c, n, path) = try Resolver(ctx).notePath(note)
            var expected: String?
            if let expect {
                let current = try c.store.read(n)
                guard contentHash(current) == expect.lowercased() else {
                    throw CLIError(
                        exit: .conflict, message: String(localized: .noteWriteConflict(path)),
                        hints: [String(localized: .noteWriteConflictHint(c.code, path))])
                }
                expected = current
            }
            try perform(spec: NoteWrite(course: c.id, note: path, text: try readText(file), expected: expected), g, ctx: ctx)
        }
    }
}
