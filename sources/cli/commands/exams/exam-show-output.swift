import FolioActions
import FolioDomain
import Foundation

extension ExamShow: QueryOutput {
    func say(_ linked: QueryLinks<Exam>, _ r: Resolver) throws {
        let e = linked.item
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
        let units = f.scopeUnits(of: e)
        if !units.isEmpty {
            FolioCLI.say(String(localized: f.isEdited(scopeOf: e) ? .examShowScopeEdited : .examShowScope))
            for u in units { FolioCLI.say("    \(u.title)") }
        } else if e.start == nil {
            FolioCLI.say(String(localized: .examShowScopeNoDate))
        }
        if !e.plan.isEmpty {
            FolioCLI.say(String(localized: .examShowPlan))
            for item in e.plan.sorted(by: { $0.day < $1.day }) { FolioCLI.say("    \(item.day)  \(item.title)") }
        }
    }
}
