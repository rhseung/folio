import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension ProblemSetCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .problemSetListAbstract), discussion: String(localized: .problemSetListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let sets = c.file.problemSets
            if g.json { return try printJSON(sets) }
            if lines {
                for s in sets { line(["\(c.code)/\(s.title)", String(localized: .problemSetListProblems(s.problems.count))]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [String(localized: .problemSetListHeaderSet), String(localized: .problemSetListHeaderProblems)], shrink: [1])
            for s in sets { t.rows.append([s.title, s.problems.map(\.number).joined(separator: " ")]) }
            t.print()
            footer(sets.count)
        }
    }
}
