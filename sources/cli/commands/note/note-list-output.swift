import FolioActions
import FolioDomain
import Foundation

extension NoteList: QueryLines {
    func lines(_ notes: [Item], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return notes.map { ["\(c.code)/\($0.path)", $0.title, $0.kind.rawValue, session($0, c.file, r)] }
    }

    func say(_ notes: [Item], _ r: Resolver) throws {
        let c = try r.course(id: course)
        courseHeader(c, catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .noteListHeaderNote), String(localized: .noteListHeaderKind),
                String(localized: .noteListHeaderSession), String(localized: .noteListHeaderPath),
            ], shrink: [3])
        for n in notes { t.rows.append([n.title, n.kind.rawValue, session(n, c.file, r), n.path]) }
        t.print()
        footer(notes.count)
    }

    private func session(_ n: Item, _ f: CourseFile, _ r: Resolver) -> String {
        f.sessionSpan(of: n.id, calendar: r.ctx.calendar) ?? ""
    }
}
