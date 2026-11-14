import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension AssignmentCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .assignmentListAbstract), discussion: String(localized: .assignmentListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .assignmentListHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .assignmentListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let items = f.assignments.filter { all || $0.status == .todo || $0.status == .doing }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            if g.json { return try printJSON(items) }
            if lines {
                for a in items {
                    line([
                        "\(c.code)/\(a.title)", a.title, a.due.map { $0.formatted(date: .numeric, time: .shortened) } ?? "",
                        a.status.rawValue,
                    ])
                }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .assignmentListHeaderAssignment), String(localized: .assignmentListHeaderDue),
                    String(localized: .assignmentListHeaderStatus), String(localized: .assignmentListHeaderComponent),
                ], shrink: [3])
            for a in items {
                let late = a.due.map { $0 < r.ctx.now } ?? false
                let due = a.due.map { when($0, now: r.ctx.now, time: true) } ?? "-"
                let open = a.status == .todo || a.status == .doing
                t.rows.append([
                    a.title, late && open ? due.plain.styled(.red) : due, a.status.rawValue.toned,
                    a.componentId.flatMap { id in f.components.first { $0.id == id }?.name } ?? a.componentGroup ?? "",
                ])
            }
            t.print()
            footer(items.count, hidden: all ? nil : String(localized: .assignmentListHidden))
        }
    }
}
