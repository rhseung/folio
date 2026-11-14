import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ComponentCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .componentListAbstract), discussion: String(localized: .componentListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let components = f.components.sorted { $0.order < $1.order }
            if g.json { return try printJSON(components) }
            if lines {
                for x in components { line(["\(c.code)/\(x.name)", "\(x.weight.formatted())%", x.group ?? ""]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .componentListHeaderComponent), String(localized: .componentListHeaderWeight),
                    String(localized: .componentListHeaderGroup), String(localized: .componentListHeaderAggregation),
                    String(localized: .componentListHeaderScores),
                ], shrink: [2])
            for x in components {
                let scores = f.scores.filter { $0.componentId == x.id }.count
                let count = x.expectedCount.map { "\(scores)/\($0)" } ?? "\(scores)"
                let aggregation = String(decoding: (try? JSONEncoder().encode(x.aggregation)) ?? Data(), as: UTF8.self).trimmingCharacters(
                    in: ["\""])
                t.rows.append([
                    x.name, bar(x.weight / 100).course(c.color) + " \(x.weight.formatted())%", x.group ?? "", aggregation, count,
                ])
            }
            t.print()
            let total = components.map(\.weight).reduce(0, +)
            footer(
                components.count,
                hidden: String(
                    localized: components.isEmpty || total == 100
                        ? .componentListTotal(total.formatted()) : .componentListTotalOff(total.formatted())))
        }
    }
}
