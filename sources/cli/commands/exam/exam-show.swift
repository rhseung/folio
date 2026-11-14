import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ExamCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .examShowAbstract), discussion: String(localized: .examShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .examShowHelpExam), valueName: "exam"), completion: Complete.exams) var exam:
            String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(exam)
            let e = try r.exam(name, in: c)
            if g.json { return try printJSON(e) }
            let f = c.file
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(e.title.styled(.bold))
            if let start = e.start {
                say(
                    String(localized: .examShowTime(when(start, now: r.ctx.now, time: true)))
                        + (e.end.map { " – \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
            }
            if !e.location.isEmpty { say(String(localized: .examShowLocation(e.location))) }
            if let comp = e.componentId.flatMap({ id in f.components.first { $0.id == id } }) {
                say(String(localized: .examShowComponent(comp.name)))
            }
            let units = UnitTree.outline(f.units).map(\.unit).filter { e.scopeUnitIds.contains($0.id) }
            if !units.isEmpty {
                say(String(localized: .examShowScope))
                for u in units { say("    \(u.title)") }
            }
            if !e.plan.isEmpty {
                say(String(localized: .examShowPlan))
                for item in e.plan.sorted(by: { $0.day < $1.day }) { say("    \(item.day)  \(item.title)") }
            }
        }
    }
}
