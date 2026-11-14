import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialCommand {
    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialLinkAbstract), discussion: String(localized: .materialLinkDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials)
        var material: String
        @Argument(help: ArgumentHelp(String(localized: .materialLinkHelpSession), valueName: "session"), completion: Complete.sessions)
        var session: String = ""
        @Option(help: ArgumentHelp(String(localized: .materialLinkHelpPages), valueName: "pages")) var pages: String?
        @Flag(help: ArgumentHelp(String(localized: .materialLinkHelpOff))) var off = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            let s = try r.session(c.local(session), in: c)
            let bounds = pages?.split(separator: "-").compactMap { Int($0) } ?? []
            guard pages == nil || (1...2).contains(bounds.count) else {
                throw CLIError(exit: .usage, message: String(localized: .materialLinkPagesFormat))
            }
            try perform(
                spec: MaterialLinkSession(
                    course: c.id, material: m.id, session: s.id, linked: !off, firstPage: bounds.first, lastPage: bounds.last),
                g, ctx: ctx)
        }
    }
}
