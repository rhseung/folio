import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialCommand {
    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialWriteAbstract), discussion: String(localized: .materialWriteDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials)
        var material: String
        @Option(help: ArgumentHelp(String(localized: .noteWriteHelpFile), valueName: "file"), completion: .file()) var file: String
        @Option(help: ArgumentHelp(String(localized: .materialWriteHelpExpect), valueName: "hash")) var expect: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            var expected: String?
            if let expect, MaterialFormat(path: m.path).isText {
                let current = try c.store.readText(m.path)
                guard contentHash(current) == expect.lowercased() else {
                    throw CLIError(
                        exit: .conflict, message: String(localized: .materialWriteConflict(m.path)),
                        hints: [String(localized: .materialWriteConflictHint(c.code, m.path))])
                }
                expected = current
            }
            try perform(spec: MaterialWrite(course: c.id, material: m.id, text: try readText(file), expected: expected), g, ctx: ctx)
        }
    }
}
