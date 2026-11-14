import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension ReviewCommand {
    struct Skip: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .reviewSkipAbstract), discussion: String(localized: .reviewSkipDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .reviewSkipHelpUnits), valueName: "unit"), completion: Complete.units) var units:
            [String]
        @Option(help: ArgumentHelp(String(localized: .reviewSkipHelpStart), valueName: "date")) var start: DateArg?
        @Option(help: ArgumentHelp(String(localized: .reviewSkipHelpEnd), valueName: "date")) var end: DateArg?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let targets = try units.map { ref in
                let (c, name) = try r.split(ref)
                return ReviewSkip.Target(course: c.id, unit: try r.unit(name, in: c).id)
            }
            try perform(spec: ReviewSkip(units: targets, start: start?.date, end: end?.date), g, ctx: ctx)
        }
    }
}
