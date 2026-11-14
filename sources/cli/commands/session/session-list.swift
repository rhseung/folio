import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension SessionCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .sessionListAbstract), discussion: String(localized: .sessionListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionListHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .sessionListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let sessions = f.sessions.sorted { $0.date < $1.date }.filter { all || !$0.isCancelled }
            if g.json { return try printJSON(sessions) }
            if lines {
                for s in sessions {
                    line([
                        "\(c.code)/\(f.reference(of: s, calendar: r.ctx.calendar))", s.date.formatted(date: .numeric, time: .shortened),
                        kindLabel(s) ?? "", f.subject(of: s) ?? "",
                    ])
                }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .sessionListHeaderSession), String(localized: .sessionListHeaderDate),
                    String(localized: .sessionListHeaderKind), String(localized: .sessionListHeaderUnits),
                    String(localized: .sessionListHeaderNotes),
                ], shrink: [3])
            for s in sessions {
                let notes = [
                    s.roughNoteId.map { _ in String(localized: .sessionListRough) },
                    s.reviewNoteId.map { _ in
                        s.reviewNoteUnfinished == true
                            ? String(localized: .sessionListReviewUnfinished) : String(localized: .sessionListReview)
                    },
                ].compactMap { $0 }
                let cells = [
                    f.reference(of: s, calendar: r.ctx.calendar), when(s.date, now: r.ctx.now, time: true),
                    kindLabel(s).map { s.isCancelled ? $0.toned : $0 } ?? "", f.subject(of: s) ?? "", notes.joined(separator: " · "),
                ]
                t.rows.append(s.date < r.ctx.now ? cells.map { $0.styled(.dim) } : cells)
            }
            t.print()
            footer(sessions.count, hidden: all ? nil : String(localized: .sessionListHidden))
        }
    }
}
