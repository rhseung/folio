import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension RequirementCommand {
    struct Accept: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .requirementAcceptAbstract), discussion: String(localized: .requirementAcceptDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .requirementAcceptHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var courses: [String] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            var ids = try courses.map { try r.course($0).id }
            if ids.isEmpty {
                let catalog = try ctx.catalog().scoped(to: ctx.transcript().graduation.programs)
                ids = RequirementAudit(courses: r.courses.map(\.course), semesters: r.semesters, catalog: catalog).suggestions.map(
                    \.courseId)
            }
            guard !ids.isEmpty else { return say(String(localized: .requirementAcceptNothing)) }
            try perform(spec: RequirementAccept(courses: ids), g, ctx: ctx)
        }
    }
}
