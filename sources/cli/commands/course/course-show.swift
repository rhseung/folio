import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CourseCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .courseShowAbstract), discussion: String(localized: .courseShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            if g.json { return try printJSON(c.course) }
            let catalog = try? r.ctx.catalog()
            courseHeader(c, catalog: catalog)
            let x = c.course
            say(String(localized: .courseShowCredits(x.credits.formatted())))
            say(String(localized: .courseShowMode(x.gradingMode.rawValue)))
            if let grade = catalog?.grade(x.finalGrade) { say(String(localized: .courseShowGrade(GradesLock.masked(grade.symbol)))) }
            let categories = x.categoryIds.compactMap { catalog?.category($0)?.name }
            if !categories.isEmpty { say(String(localized: .courseShowCategories(categories.joined(separator: ", ")))) }
            if x.reviews == false { say(String(localized: .courseShowReviewsOff)) }
            if !x.schedule.isEmpty {
                say(String(localized: .courseShowSchedule))
                for t in x.schedule {
                    say(
                        "    \(ClassTime.weekdayNames[t.weekday - 1]) \(String(format: "%02d:%02d–%02d:%02d", t.startMinute / 60, t.startMinute % 60, t.endMinute / 60, t.endMinute % 60)) \(t.room)"
                    )
                }
            }
            if x.sharingApproved == true { say(String(localized: .courseShowSharingApproved)) }
            if !x.memo.isEmpty { say(String(localized: .courseShowMemo(x.memo))) }
        }
    }
}
