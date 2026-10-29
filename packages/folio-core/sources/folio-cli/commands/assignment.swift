import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct AssignmentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assignment", abstract: String(localized: .assignmentAbstract),
        subcommands: [List.self, Show.self, Set.self] + GeneratedCommands.assignment)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .assignmentListAbstract), discussion: String(localized: .assignmentListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .assignmentListHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .assignmentListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            let items = f.assignments.filter { all || $0.status == .todo || $0.status == .doing }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            if g.json { return try printJSON(items) }
            if lines {
                for a in items { line(["\(c.code)/\(a.title)", a.title, a.due.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", a.status.rawValue]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .assignmentListHeaderAssignment), String(localized: .assignmentListHeaderDue), String(localized: .assignmentListHeaderStatus), String(localized: .assignmentListHeaderComponent)], shrink: [3])
            for a in items {
                let late = a.due.map { $0 < r.ctx.now } ?? false
                let due = a.due.map { when($0, now: r.ctx.now, time: true) } ?? "-"
                let open = a.status == .todo || a.status == .doing
                t.rows.append([a.title, late && open ? due.plain.styled(.red) : due, a.status.rawValue.toned,
                               a.componentId.flatMap { id in f.components.first { $0.id == id }?.name } ?? a.componentGroup ?? ""])
            }
            t.print()
            footer(items.count, hidden: all ? nil : String(localized: .assignmentListHidden))
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .assignmentShowAbstract), discussion: String(localized: .assignmentShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .assignmentShowHelpAssignment), valueName: "assignment"), completion: Complete.assignments) var assignment: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(assignment)
            let a = try r.assignment(name, in: c)
            if g.json { return try printJSON(a) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(a.title.styled(.bold))
            if let due = a.due { say(String(localized: .assignmentShowDue(when(due, now: r.ctx.now, time: true)))) }
            say(String(localized: .assignmentShowStatus(a.status.rawValue.toned)))
            if a.repeats == .weekly { say(String(localized: .assignmentShowWeekly)) }
            if !a.memo.isEmpty { say(String(localized: .assignmentShowMemo(a.memo))) }
            let scores = f.scores.filter { $0.assignmentId == a.id }
            if !scores.isEmpty {
                say(String(localized: .assignmentShowScores))
                for s in scores {
                    let comp = f.components.first { $0.id == s.componentId }?.name ?? ""
                    say("    \(comp)  \(GradesLock.masked("\(s.score.formatted())/\(s.max.formatted())"))")
                }
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .assignmentSetAbstract), discussion: String(localized: .assignmentSetDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .assignmentSetHelpAssignment), valueName: "assignment"), completion: Complete.assignments) var assignment: String = ""
        @Option(help: ArgumentHelp(String(localized: .assignmentSetHelpTitle), valueName: "title")) var title: String?
        @Option(help: ArgumentHelp(String(localized: .assignmentSetHelpDue), valueName: "when")) var due: Clearable<DateArg>?
        @Option(help: ArgumentHelp(String(localized: .commonHelpStatus))) var status: AssignmentStatus?
        @Option(help: ArgumentHelp(String(localized: .assignmentSetHelpRepeats))) var repeats: Clearable<AssignmentRepeat>?
        @Option(help: ArgumentHelp(String(localized: .assignmentSetHelpComponent), valueName: "item")) var component: Clearable<String>?
        @Option(help: ArgumentHelp(String(localized: .assignmentSetHelpGroup), valueName: "group")) var group: Clearable<String>?
        @Option(help: ArgumentHelp(String(localized: .assignmentSetHelpScore), valueName: "score")) var score: [String] = []
        @Option(help: ArgumentHelp(String(localized: .commonHelpMemo), valueName: "memo")) var memo: String?

        func run() throws {
            guard component == nil || group == nil else { throw CLIError(exit: .usage, message: String(localized: .assignmentSetComponentOrGroup)) }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(assignment)
            let a = try r.assignment(name, in: c)
            let f = try c.requireFile()
            var componentId = a.componentId, componentGroup = a.componentGroup
            if let component { componentId = try component.value.map { try r.component($0, in: c).id }; componentGroup = nil }
            if let group {
                guard group.value.map({ g in f.components.contains { $0.group == g } }) ?? true else {
                    throw CLIError(exit: .notFound, message: String(localized: .assignmentSetGroupNotFound(group.value ?? "")),
                                   candidates: Array(Swift.Set(f.components.compactMap(\.group))).sorted())
                }
                (componentGroup, componentId) = (group.value, group.value == nil ? componentId : nil)
            }
            // The sheet always sends every covered component and its scores; one left out would lose its score.
            let covered = componentGroup.map { g in f.components.filter { $0.group == g }.map(\.id) } ?? componentId.map { [$0] } ?? []
            var scores = f.scores.filter { $0.assignmentId == a.id }.map { AssignmentSave.Score(component: $0.componentId, score: $0.score, max: $0.max) }
            if score == ["none"] { scores = [] }
            for s in score where s != "none" {
                let (target, value) = s.firstIndex(of: ":").map { (String(s[..<$0]), String(s[s.index(after: $0)...])) } ?? (nil, s)
                let parts = value.split(separator: "/").compactMap { Double($0) }
                guard parts.count == 2 else { throw CLIError(exit: .usage, message: String(localized: .assignmentSetScoreFormat(s))) }
                let id: UUID
                if let target { id = try r.component(target, in: c).id } else if covered.count == 1 { id = covered[0] } else {
                    throw CLIError(exit: .usage, message: covered.isEmpty ? String(localized: .assignmentSetNoComponent) : String(localized: .assignmentSetGroupScoreFormat))
                }
                guard covered.contains(id) else { throw CLIError(exit: .rule, message: String(localized: .assignmentSetNotCovered(target ?? ""))) }
                scores.removeAll { $0.component == id }
                scores.append(AssignmentSave.Score(component: id, score: parts[0], max: parts[1]))
            }
            try perform(spec: AssignmentSave(course: c.id, assignment: a.id, title: title ?? a.title, due: due.map(\.value?.date) ?? a.due, status: status ?? a.status,
                                       repeats: repeats.map(\.value) ?? a.repeats, componentId: componentId, componentGroup: componentGroup, memo: memo ?? a.memo,
                                       components: covered, scores: scores),
                        g, ctx: ctx)
        }
    }
}
