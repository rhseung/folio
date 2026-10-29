import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

/// Read-only: grades and credits are changed on the course (`folio course set`), the term on the semester.
struct TranscriptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcript", abstract: String(localized: .transcriptAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.transcript)

    struct Row: Encodable {
        var semester: String
        var code: String
        var courseId: UUID
        var title: String
        var credits: Double
        var gradingMode: GradingMode
        var grade: String?
    }

    static func rows(_ r: Resolver, in semesters: [Semester]) throws -> [Row] {
        let catalog = try r.ctx.catalog()
        return semesters.flatMap { s in
            r.courses.filter { $0.course.semesterId == s.id }.sorted { $0.code < $1.code }.map { c in
                Row(semester: s.folder?.name ?? String(localized: .semesterRecognized), code: c.code, courseId: c.id, title: c.course.title, credits: c.course.credits,
                    gradingMode: c.course.gradingMode, grade: catalog.grade(c.course.finalGrade)?.symbol)
            }
        }
    }

    static func print(_ rows: [Row], semester: Bool) {
        var t = Table(header: (semester ? [String(localized: .transcriptHeaderSemester)] : []) + [String(localized: .transcriptHeaderCourse), String(localized: .transcriptHeaderName), String(localized: .transcriptHeaderCredits), String(localized: .transcriptHeaderMode), String(localized: .transcriptHeaderGrade)], shrink: [semester ? 2 : 1])
        for x in rows {
            t.rows.append((semester ? [x.semester] : []) + [x.code, x.title, x.credits.formatted(), x.gradingMode.rawValue.toned, x.grade ?? "-"])
        }
        t.print()
        footer(rows.count)
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .transcriptListAbstract), discussion: String(localized: .transcriptListDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let r = Resolver(try CLI.context(g))
            try GradesLock.require()
            let rows = try TranscriptCommand.rows(r, in: r.semesters)
            if g.json { return try printJSON(rows) }
            TranscriptCommand.print(rows, semester: true)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .transcriptShowAbstract), discussion: String(localized: .transcriptShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .transcriptShowHelpSemester), valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let s = try r.semester(semester)
            try GradesLock.require()
            let rows = try TranscriptCommand.rows(r, in: [s])
            let summary = GPACalculator.semester(s, courses: try r.ctx.gist.allCourses(), catalog: try r.ctx.catalog())
            struct Out: Encodable { var courses: [Row]; var totalCredits: Double; var effectiveCredits: Double; var gpa: Double? }
            if g.json { return try printJSON(Out(courses: rows, totalCredits: summary.totalCredits, effectiveCredits: summary.effectiveCredits, gpa: summary.gpa)) }
            say((s.folder?.name ?? String(localized: .semesterRecognized)).styled(.bold) + "  " + String(localized: .transcriptShowSummary(summary.totalCredits.formatted(), summary.effectiveCredits.formatted(), GPACalculator.label(summary.gpa))).styled(.dim))
            TranscriptCommand.print(rows, semester: false)
        }
    }
}
