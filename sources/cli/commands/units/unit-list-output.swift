import FolioActions
import FolioDomain
import Foundation

extension UnitList: QueryLines {
    func lines(_ outline: Outline, _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return outline.items.map { u, _ in
            ["\(c.code)/\(u.title)", u.title, String(localized: .unitListSessions(outline.file.sessions(of: u.id).count))]
        }
    }

    func say(_ outline: Outline, _ r: Resolver) throws {
        courseHeader(try r.course(id: course), catalog: try? r.ctx.catalog())
        let items = outline.items
        for (i, item) in items.enumerated() {
            FolioCLI.say(
                treePrefix(items.map(\.depth), at: i) + item.unit.title
                    + (sessions(item.unit, outline).isEmpty
                        ? "" : String(localized: .unitListSessionsIndented(sessions(item.unit, outline).count)).styled(.dim)))
        }
        footer(items.count)
    }

    private func sessions(_ unit: FolioDomain.Unit, _ outline: Outline) -> [Session] { outline.file.sessions(of: unit.id) }
}
