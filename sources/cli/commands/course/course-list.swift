import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CourseCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .courseListAbstract), discussion: String(localized: .courseListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(
            help: ArgumentHelp(String(localized: .courseListHelpSemester), valueName: "semester"), completion: .custom(Complete.semesters))
        var semester: String?
        @Flag(help: ArgumentHelp(String(localized: .courseListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let semesterId = all ? nil : try r.semester(semester).id
            let courses = r.courses.filter { semesterId == nil || $0.course.semesterId == semesterId }
            if g.json { return try printJSON(courses.map(\.course)) }
            if lines {
                for c in courses { line([c.code, c.course.title, String(localized: .courseListCredits(c.course.credits.formatted()))]) }
                return
            }
            let catalog = try? r.ctx.catalog()
            var t = Table(
                header: [
                    "", String(localized: .courseListHeaderCode), String(localized: .courseListHeaderCourse),
                    String(localized: .courseListHeaderCredits), String(localized: .courseListHeaderMode),
                    String(localized: .courseListHeaderGrade),
                ], shrink: [2])
            for c in courses {
                t.rows.append([
                    "●".course(c.color), c.tag, c.course.title, c.course.credits.formatted(), c.course.gradingMode.rawValue.toned,
                    catalog?.grade(c.course.finalGrade).map { GradesLock.masked($0.symbol) } ?? "",
                ])
            }
            t.print()
            footer(courses.count, hidden: all ? nil : String(localized: .courseListHiddenAll))
        }
    }
}
