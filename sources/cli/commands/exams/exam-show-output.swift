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
        if let period = e.planPeriod, let start = period.start.date(in: r.ctx.calendar), let end = period.end.date(in: r.ctx.calendar) {
            let days = (CourseFile.day(start, calendar: r.ctx.calendar), CourseFile.day(end, calendar: r.ctx.calendar))
            FolioCLI.say(String(localized: period.after == .mock ? .examShowPeriodMock(days.0, days.1) : .examShowPeriod(days.0, days.1)))
        }
        let items = e.plan.filter { !$0.isRemoved }
        if !items.isEmpty {
            let today = r.settings.studyDay(of: r.ctx.now, calendar: r.ctx.calendar)
            let done = linked.planDone
            FolioCLI.say(String(localized: .examShowPlan))
            for item in items.sorted(by: { $0.day < $1.day }) {
                let finished = done.contains(item.id)
                let mark =
                    finished
                    ? String(localized: .examShowPlanDone)
                    : item.lateFrom(today: today, done: false) == nil ? "" : String(localized: .examShowPlanLate)
                let line = "    \(item.day)  \(f.title(of: item))" + (mark.isEmpty ? "" : "  \(mark)")
                FolioCLI.say(finished ? line.styled(.dim) : line)
            }
        }
    }
}
