import FolioActions
import FolioDomain
import Foundation

extension ComponentList: QueryLines {
    func lines(_ components: [GradeComponent], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return components.map { ["\(c.code)/\($0.name)", "\($0.weight.formatted())%", $0.group ?? ""] }
    }

    func say(_ components: [GradeComponent], _ r: Resolver) throws {
        let c = try r.course(id: course)
        let f = c.file
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
            let aggregation = (String(bytes: (try? JSONEncoder().encode(x.aggregation)) ?? Data(), encoding: .utf8) ?? "")
                .trimmingCharacters(
                    in: ["\""])
            t.rows.append([x.name, bar(x.weight / 100).course(c.color) + " \(x.weight.formatted())%", x.group ?? "", aggregation, count])
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
