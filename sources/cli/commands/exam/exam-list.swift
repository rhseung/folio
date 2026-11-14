import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ExamCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .examListAbstract), discussion: String(localized: .examListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .examListHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let file = c.file
            let exams = file.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            func component(_ e: Exam) -> String { e.componentId.flatMap { id in file.components.first { $0.id == id }?.name } ?? "" }
            if g.json { return try printJSON(exams) }
            if lines {
                for e in exams {
                    line([
                        "\(c.code)/\(e.title)", e.title, e.start.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", component(e),
                    ])
                }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .examListHeaderExam), String(localized: .examListHeaderTime),
                    String(localized: .examListHeaderComponent), String(localized: .examListHeaderLocation),
                    String(localized: .examListHeaderScope),
                ], shrink: [3])
            for e in exams {
                let cells = [
                    e.title, e.start.map { when($0, now: r.ctx.now, time: true) } ?? "-", component(e).toned, e.location,
                    e.scopeUnitIds.isEmpty ? "" : String(localized: .examListUnits(e.scopeUnitIds.count)),
                ]
                t.rows.append((e.end ?? e.start).map { $0 < r.ctx.now } ?? false ? cells.map { $0.styled(.dim) } : cells)
            }
            t.print()
            footer(exams.count)
        }
    }
}
