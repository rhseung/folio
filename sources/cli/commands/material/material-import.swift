import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialCommand {
    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialImportAbstract), discussion: String(localized: .materialImportDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String
        @Argument(help: ArgumentHelp(String(localized: .materialImportHelpFiles), valueName: "file"), completion: .file()) var files:
            [String]
        @Option(help: ArgumentHelp(String(localized: .materialImportHelpFolder), valueName: "folder"), completion: .directory) var folder:
            String
        @Option(help: ArgumentHelp(String(localized: .materialImportHelpSession), valueName: "session"), completion: Complete.sessions)
        var session: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let s = try session.map { try r.session(c.local($0), in: c).id }
            try perform(
                spec: MaterialImport(course: c.id, items: files.map { ImportItem(file: absolute($0), folder: folder, session: s) }), g,
                ctx: ctx)
        }
    }
}
