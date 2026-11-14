import FolioActions
import FolioDomain
import Foundation

extension ProblemSetList: QueryLines {
    func lines(_ sets: [ProblemSet], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return sets.map { ["\(c.code)/\($0.title)", String(localized: .problemSetListProblems($0.problems.count))] }
    }

    func say(_ sets: [ProblemSet], _ r: Resolver) throws {
        courseHeader(try r.course(id: course), catalog: try? r.ctx.catalog())
        var t = Table(header: [String(localized: .problemSetListHeaderSet), String(localized: .problemSetListHeaderProblems)], shrink: [1])
        for s in sets { t.rows.append([s.title, s.problems.map(\.number).joined(separator: " ")]) }
        t.print()
        footer(sets.count)
    }
}
