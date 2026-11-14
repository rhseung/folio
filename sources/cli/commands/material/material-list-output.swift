import FolioActions
import FolioDomain
import Foundation

extension MaterialList: QueryLines {
    func lines(_ materials: [Material], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return materials.map { m in ["\(c.code)/\(m.path)", m.role?.rawValue ?? "", m.status.rawValue, sessions(m, c.file, r)] }
    }

    func say(_ materials: [Material], _ r: Resolver) throws {
        let c = try r.course(id: course)
        courseHeader(c, catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .materialListHeaderPath), String(localized: .materialListHeaderRole),
                String(localized: .materialListHeaderStatus), String(localized: .materialListHeaderSession),
            ], shrink: [3])
        for m in materials {
            t.rows.append([m.path, m.role?.rawValue ?? "", m.status.rawValue.toned(m.status.tone), sessions(m, c.file, r)])
        }
        t.print()
        footer(materials.count, hidden: all ? nil : String(localized: .materialListHidden))
    }

    private func sessions(_ m: Material, _ f: CourseFile, _ r: Resolver) -> String {
        f.sessions.filter { s in s.materials.contains { $0.materialId == m.id } }.map { f.reference(of: $0, calendar: r.ctx.calendar) }
            .joined(separator: ", ")
    }
}
