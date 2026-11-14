import FolioActions
import FolioDomain
import Foundation

extension ExamShow: QueryOutput {
    func say(_ e: Exam, _ r: Resolver) throws {
        guard let c = r.courses.first(where: { $0.id == course }) else { return }
        let f = c.file
        courseHeader(c, catalog: try? r.ctx.catalog())
        FolioCLI.say(e.title.styled(.bold))
        if let start = e.start {
            FolioCLI.say(
                String(localized: .examShowTime(when(start, now: r.ctx.now, time: true, settings: r.settings)))
                    + (e.end.map { " – \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
        }
        if !e.location.isEmpty { FolioCLI.say(String(localized: .examShowLocation(e.location))) }
        if let comp = e.componentId.flatMap({ id in f.components.first { $0.id == id } }) {
            FolioCLI.say(String(localized: .examShowComponent(comp.name)))
        }
        let units = UnitTree.outline(f.units).map(\.unit).filter { e.scopeUnitIds.contains($0.id) }
        if !units.isEmpty {
            FolioCLI.say(String(localized: .examShowScope))
            for u in units { FolioCLI.say("    \(u.title)") }
        }
        if !e.plan.isEmpty {
            FolioCLI.say(String(localized: .examShowPlan))
            for item in e.plan.sorted(by: { $0.day < $1.day }) { FolioCLI.say("    \(item.day)  \(item.title)") }
        }
    }
}
