import FolioActions
import FolioDomain
import Foundation

extension SessionShow: QueryOutput {
    func say(_ linked: QueryLinks<Session>, _ r: Resolver) throws {
        let s = linked.item
        let c = try r.course(id: course)
        let f = c.file
        courseHeader(c, catalog: try? r.ctx.catalog())
        FolioCLI.say(f.title(of: s, calendar: r.ctx.calendar).styled(.bold))
        FolioCLI.say(String(localized: .sessionShowDate(when(s.date, now: r.ctx.now, time: true, settings: r.settings))))
        switch s.kind {
        case .cancelled: FolioCLI.say(String(localized: .sessionShowCancelled))
        case .makeup: FolioCLI.say(String(localized: .sessionShowMakeup))
        case .lecture: break
        }
        if let end = s.end(schedule: f.course.schedule, calendar: r.ctx.calendar) {
            FolioCLI.say(String(localized: .sessionShowEnd(end.formatted(date: .omitted, time: .shortened))))
        }
        if let link = s.link(schedule: f.course.schedule, calendar: r.ctx.calendar) {
            FolioCLI.say(String(localized: .sessionShowLink(link.absoluteString)))
        }
        let units = f.units(of: s).map(\.title)
        if !units.isEmpty {
            FolioCLI.say(String(localized: .sessionShowUnits))
            for u in units { FolioCLI.say("    \(u)") }
        }
        let materials = s.materials.compactMap { link in f.materials.first { $0.id == link.materialId }.map { ($0, link) } }
        if !materials.isEmpty {
            FolioCLI.say(String(localized: .sessionShowMaterials))
            for (m, link) in materials {
                let pages = link.pages.map { " p.\($0.lowerBound)\($0.count > 1 ? "-\($0.upperBound)" : "")" } ?? ""
                FolioCLI.say("    \((m.path as NSString).lastPathComponent)\(pages)")
            }
        }
    }
}
