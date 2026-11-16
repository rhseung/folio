import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialCommand {
    struct Relink: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialRelinkAbstract), discussion: String(localized: .materialRelinkDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials)
        var material: String
        @Argument(help: ArgumentHelp(String(localized: .materialRelinkHelpFile), valueName: "file"), completion: .file()) var file: String

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            let path = file.hasPrefix("/") || file.hasPrefix("~") ? absolute(file) : c.store.url.appending(path: file).path
            try perform(spec: MaterialRelink(course: c.id, material: m.id, file: path), g, ctx: ctx)
        }
    }
}
