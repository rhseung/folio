import FolioActions
import FolioDomain
import Foundation

extension UnitShow: QueryOutput {
    func say(_ linked: QueryLinks<FolioDomain.Unit>, _ r: Resolver) throws {
        let u = linked.item
        guard let c = r.courses.first(where: { $0.id == course }) else { return }
        let f = c.file
        courseHeader(c, catalog: try? r.ctx.catalog())
        FolioCLI.say(u.title.styled(.bold))
        if let parent = u.parentId.flatMap({ id in f.units.first { $0.id == id } }) {
            FolioCLI.say(String(localized: .unitShowParent(parent.title)))
        }
        let children = f.units.filter { $0.parentId == u.id }.sorted { $0.order < $1.order }
        let sessions = f.sessions(of: u.id).map { f.reference(of: $0, calendar: r.ctx.calendar) }
        let pages = u.lecturePages.compactMap { p in
            f.materials.first { $0.id == p.materialId }.map { "\(($0.path as NSString).lastPathComponent) p.\(p.firstPage)-\(p.lastPage)" }
        }
        for (title, names) in [
            (String(localized: .unitShowChildren), children.map(\.title)),
            (String(localized: .unitShowSessions), sessions),
            (String(localized: .unitShowExams), f.exams(scoping: u.id).map(\.title)),
            (String(localized: .unitShowPages), pages),
        ] where !names.isEmpty {
            FolioCLI.say("  \(title)")
            for n in names { FolioCLI.say("    \(n)") }
        }
    }
}
