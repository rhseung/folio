import FolioActions
import FolioDomain
import Foundation

extension AssignmentList: QueryLines {
    func lines(_ items: [Assignment], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return items.map { a in
            ["\(c.code)/\(a.title)", a.title, a.due.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", a.status.rawValue]
        }
    }

    func say(_ items: [Assignment], _ r: Resolver) throws {
        let c = try r.course(id: course)
        let f = c.file
        courseHeader(c, catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .assignmentListHeaderAssignment), String(localized: .assignmentListHeaderDue),
                String(localized: .assignmentListHeaderStatus), String(localized: .assignmentListHeaderComponent),
            ], shrink: [3])
        for a in items {
            let late = a.due.map { $0 < r.ctx.now } ?? false
            let due = a.due.map { when($0, now: r.ctx.now, time: true, settings: r.settings) } ?? "-"
            let open = a.status == .todo || a.status == .doing
            t.rows.append([
                a.title, late && open ? due.plain.styled(.red) : due, a.status.rawValue.toned(a.status.tone),
                a.componentId.flatMap { id in f.components.first { $0.id == id }?.name } ?? a.componentGroup ?? "",
            ])
        }
        t.print()
        footer(items.count, hidden: all ? nil : String(localized: .assignmentListHidden))
    }
}
