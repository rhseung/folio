import FolioActions
import FolioDomain
import Foundation

extension ScoreList: QueryLines {
    func lines(_ scores: [ScoreEntry], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return scores.map { s in
            ["\(c.code)/\(s.title.isEmpty ? s.id.uuidString : s.title)", name(s, c.file), s.title, points(s)]
        }
    }

    func say(_ scores: [ScoreEntry], _ r: Resolver) throws {
        let c = try r.course(id: course)
        courseHeader(c, catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .scoreListHeaderComponent), String(localized: .scoreListHeaderTitle),
                String(localized: .scoreListHeaderScore), String(localized: .scoreListHeaderDate),
            ], shrink: [1])
        for s in scores { t.rows.append([name(s, c.file), s.title, points(s), s.date?.description ?? ""]) }
        t.print()
        footer(scores.count)
    }

    private func name(_ s: ScoreEntry, _ f: CourseFile) -> String { f.components.first { $0.id == s.componentId }?.name ?? "" }

    private func points(_ s: ScoreEntry) -> String {
        s.excused ? String(localized: .scoreListExcused) : "\(s.score.formatted())/\(s.max.formatted())"
    }
}
