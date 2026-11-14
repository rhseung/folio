import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension TranscriptCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .transcriptShowAbstract), discussion: String(localized: .transcriptShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .transcriptShowHelpSemester), valueName: "semester"),
            completion: .custom(Complete.semesters)) var semester: String?

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let s = try r.semester(semester)
            try GradesLock.require()
            let rows = try TranscriptCommand.rows(r, in: [s])
            let summary = GPACalculator.semester(s, courses: try r.ctx.gist.allCourses(), catalog: try r.ctx.catalog())
            struct Out: Encodable { var courses: [Row]; var totalCredits: Double; var effectiveCredits: Double; var gpa: Double? }
            if g.json {
                return try printJSON(
                    Out(courses: rows, totalCredits: summary.totalCredits, effectiveCredits: summary.effectiveCredits, gpa: summary.gpa))
            }
            say(
                (s.folder?.name ?? s.source ?? String(localized: .semesterRecognized)).styled(.bold) + "  "
                    + String(
                        localized: .transcriptShowSummary(
                            summary.totalCredits.formatted(), summary.effectiveCredits.formatted(), GPACalculator.label(summary.gpa))
                    ).styled(.dim))
            TranscriptCommand.print(rows, semester: false)
        }
    }
}
