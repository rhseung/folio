import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension ProblemSetCommand {
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .problemSetAddAbstract), discussion: String(localized: .problemSetAddDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String
        @Argument(help: ArgumentHelp(String(localized: .problemSetAddHelpTitle), valueName: "title")) var title: String
        @Option(parsing: .upToNextOption, help: ArgumentHelp(String(localized: .problemSetAddHelpProblems), valueName: "number"))
        var problems: [String] = []
        @Option(help: .hidden) var id: UUID?

        func run() throws {
            let ctx = try CLI.context(g)
            let c = try Resolver(ctx).course(course)
            let set = ProblemSet(
                id: id ?? UUID(), device: ctx.device, at: ctx.now, title: title, problems: problems.map { .init(number: $0) })
            try perform(spec: ProblemSetSave(course: c.id, set: set), g, ctx: ctx)
        }
    }
}
