import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ScoreCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .scoreListAbstract), discussion: String(localized: .scoreListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            try GradesLock.require()
            let order = Dictionary(f.components.map { ($0.id, $0.order) }, uniquingKeysWith: { a, _ in a })
            let scores = f.scores.sorted {
                (order[$0.componentId] ?? 0, $0.date?.description ?? "") < (order[$1.componentId] ?? 0, $1.date?.description ?? "")
            }
            if g.json { return try printJSON(scores) }
            let name = { (s: ScoreEntry) in f.components.first { $0.id == s.componentId }?.name ?? "" }
            let points = { (s: ScoreEntry) in
                s.excused ? String(localized: .scoreListExcused) : "\(s.score.formatted())/\(s.max.formatted())"
            }
            if lines {
                for s in scores { line(["\(c.code)/\(s.title.isEmpty ? s.id.uuidString : s.title)", name(s), s.title, points(s)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .scoreListHeaderComponent), String(localized: .scoreListHeaderTitle),
                    String(localized: .scoreListHeaderScore), String(localized: .scoreListHeaderDate),
                ], shrink: [1])
            for s in scores { t.rows.append([name(s), s.title, points(s), s.date?.description ?? ""]) }
            t.print()
            footer(scores.count)
        }
    }
}
