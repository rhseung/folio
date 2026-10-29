import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct ExamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exam", abstract: String(localized: .examAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.exam + [Scope.self, Plan.self, PlanCheck.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .examListAbstract), discussion: String(localized: .examListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .examListHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let exams = try c.requireFile().exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            if g.json { return try printJSON(exams) }
            if lines {
                for e in exams { line(["\(c.code)/\(e.title)", e.title, e.start.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", e.kind.rawValue]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .examListHeaderExam), String(localized: .examListHeaderTime), String(localized: .examListHeaderKind), String(localized: .examListHeaderLocation), String(localized: .examListHeaderScope)], shrink: [3])
            for e in exams {
                let cells = [e.title, e.start.map { when($0, now: r.ctx.now, time: true) } ?? "-", e.kind.rawValue.toned, e.location,
                             e.scopeUnitIds.isEmpty ? "" : String(localized: .examListUnits(e.scopeUnitIds.count))]
                t.rows.append((e.end ?? e.start).map { $0 < r.ctx.now } ?? false ? cells.map { $0.styled(.dim) } : cells)
            }
            t.print()
            footer(exams.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .examShowAbstract), discussion: String(localized: .examShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .examShowHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(exam)
            let e = try r.exam(name, in: c)
            if g.json { return try printJSON(e) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(e.title.styled(.bold))
            say(String(localized: .examShowKind(e.kind.rawValue)))
            if let start = e.start { say(String(localized: .examShowTime(when(start, now: r.ctx.now, time: true))) + (e.end.map { " – \($0.formatted(date: .omitted, time: .shortened))" } ?? "")) }
            if !e.location.isEmpty { say(String(localized: .examShowLocation(e.location))) }
            if let comp = e.componentId.flatMap({ id in f.components.first { $0.id == id } }) { say(String(localized: .examShowComponent(comp.name))) }
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

    struct Scope: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .examScopeAbstract), discussion: String(localized: .examScopeDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String = ""
        @Option(name: .customLong("unit"), help: ArgumentHelp(String(localized: .examScopeHelpUnits), valueName: "unit"), completion: Complete.units) var units: [String] = []
        @Flag(help: ArgumentHelp(String(localized: .examScopeHelpOff))) var off = false
        @Flag(help: ArgumentHelp(String(localized: .examScopeHelpTaught))) var taught = false

        func run() throws {
            guard !(taught && !units.isEmpty), !(taught && off) else {
                throw CLIError(exit: .usage, message: String(localized: .examScopeUnitOrTaught))
            }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(exam)
            let e = try r.exam(name, in: c)
            if taught {
                try perform(spec: ExamScopeTaught(course: c.id, exam: e.id), g, ctx: ctx)
                return
            }
            let ids = try r.many(units, from: try c.requireFile().units.map(\.title), what: "단원").map { try r.unit($0, in: c).id }
            try performAll(ids.map { ExamScope(course: c.id, exam: e.id, unit: $0, included: !off) }, g, ctx: ctx,
                           done: off ? String(localized: .examScopeRemoved(ids.count)) : String(localized: .examScopeAdded(ids.count)))
        }
    }

    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .examPlanAbstract), subcommands: GeneratedCommands.examPlan + [Remove.self])

        struct Remove: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "rm", abstract: String(localized: .examPlanRmAbstract), discussion: String(localized: .examPlanRmDiscussion))
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp(String(localized: .commonHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String
            @Argument(help: ArgumentHelp(String(localized: .commonHelpItem), valueName: "item")) var item: String = ""

            func run() throws {
                let ctx = try CLI.context(g)
                let r = Resolver(ctx)
                let (c, name) = try r.split(exam)
                let e = try r.exam(name, in: c)
                let i = try r.planItem(item, in: e, course: c)
                try perform(spec: ExamPlanRemove(course: c.id, exam: e.id, item: i.id), g, ctx: ctx)
            }
        }
    }

    struct PlanCheck: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "plan-check", abstract: String(localized: .examPlanCheckAbstract), discussion: String(localized: .examPlanCheckDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpItem), valueName: "item")) var item: String = ""
        @Flag(help: ArgumentHelp(String(localized: .examPlanCheckHelpUndo))) var undo = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(exam)
            let i = try r.planItem(item, in: try r.exam(name, in: c), course: c)
            try perform(ExamPlanCheck(course: c.id, item: i.id, done: !undo), g, ctx: ctx, done: undo ? String(localized: .examPlanCheckUndone(i.title)) : String(localized: .examPlanCheckDone(i.title)))
        }
    }
}

extension Resolver {
    func planItem(_ name: String, in exam: Exam, course c: CourseRef) throws -> ExamPlanItem {
        try pick(name, exam.plan, what: "공부 계획 항목", names: { [$0.title] }, ref: { "\(c.code)/\(exam.title) \($0.title)" })
    }
}
