import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension SemesterCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .semesterListAbstract), discussion: String(localized: .semesterListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let semesters = r.semesters
            if g.json { return try printJSON(semesters) }
            let span = { (s: Semester) in [s.start?.description, s.end?.description].map { $0 ?? "?" }.joined(separator: " – ") }
            if lines {
                for s in semesters { line([s.folder?.name ?? s.id.uuidString, "\(s.year) \(s.term.rawValue)", span(s)]) }
                return
            }
            let current = try? r.currentSemester().id
            var t = Table(header: [
                String(localized: .semesterListHeaderSemester), String(localized: .semesterListHeaderName),
                String(localized: .semesterListHeaderSpan),
            ])
            for s in semesters {
                let cells = [s.folder?.name ?? s.source ?? String(localized: .semesterRecognized), "\(s.year) \(s.term.rawValue)", span(s)]
                t.rows.append(s.id == current ? cells.map { $0.styled(.bold) } : cells)
            }
            t.print()
            footer(semesters.count)
        }
    }
}
