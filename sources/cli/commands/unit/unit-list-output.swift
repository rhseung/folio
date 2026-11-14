import FolioActions
import FolioDomain
import Foundation

extension UnitList: QueryLines {
    func lines(_ outline: Outline, _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return outline.items.map { u, _ in ["\(c.code)/\(u.title)", u.title, String(localized: .unitListSessions(u.sessionIds.count))] }
    }

    func say(_ outline: Outline, _ r: Resolver) throws {
        courseHeader(try r.course(id: course), catalog: try? r.ctx.catalog())
        let items = outline.items
        for (i, item) in items.enumerated() {
            FolioCLI.say(
                treePrefix(items.map(\.depth), at: i) + item.unit.title
                    + (item.unit.sessionIds.isEmpty
                        ? "" : String(localized: .unitListSessionsIndented(item.unit.sessionIds.count)).styled(.dim)))
        }
        footer(items.count)
    }
}
