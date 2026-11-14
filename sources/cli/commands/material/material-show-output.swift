import FolioActions
import FolioDomain
import Foundation

extension MaterialShow: QueryOutput {
    func say(_ shown: Shown, _ r: Resolver) throws {
        let m = shown.material
        let c = try r.course(id: course)
        let f = c.file
        courseHeader(c, catalog: try? r.ctx.catalog())
        FolioCLI.say(m.path.link(c.store.url.appending(path: m.path)).styled(.bold))
        FolioCLI.say(String(localized: .materialShowRole(m.role?.rawValue ?? "-")))
        if let format = m.format { FolioCLI.say(String(localized: .materialShowFormat(Self.label(format)))) }
        FolioCLI.say(String(localized: .materialShowStatus(m.status.rawValue.toned(m.status.tone))))
        let sessions = f.sessionLinks(of: m.id)
        if !sessions.isEmpty {
            FolioCLI.say(String(localized: .materialShowSessions))
            for (s, link) in sessions {
                let pages = link.firstPage.map { first in " p.\(first)\(link.lastPage.map { "-\($0)" } ?? "")" } ?? ""
                FolioCLI.say("    \(f.reference(of: s, calendar: r.ctx.calendar))\(pages)")
            }
        }
        let units = m.unitIds.compactMap { id in f.units.first { $0.id == id }?.title }
        if !units.isEmpty {
            FolioCLI.say(String(localized: .materialShowUnits))
            for u in units { FolioCLI.say("    \(u)") }
        }
    }

    static func label(_ format: MaterialFormat) -> String {
        if case .code(let language) = format { return "\(format.name) (\(language))" }
        return format.name
    }
}
