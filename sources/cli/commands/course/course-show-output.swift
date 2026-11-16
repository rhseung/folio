import FolioActions
import FolioCore
import FolioDomain
import Foundation

extension CourseShow: QueryOutput {
    func say(_ x: Course, _ r: Resolver) throws {
        let catalog = try? r.ctx.catalog()
        if let c = r.courses.first(where: { $0.id == x.id }) { courseHeader(c, catalog: catalog) }
        FolioCLI.say(String(localized: .courseShowCredits(x.credits.formatted())))
        FolioCLI.say(String(localized: .courseShowMode(x.gradingMode.rawValue)))
        if let grade = catalog?.grade(x.finalGrade) { FolioCLI.say(String(localized: .courseShowGrade(GradesLock.masked(grade.symbol)))) }
        let categories = x.categoryIds.compactMap { catalog?.category($0)?.name }
        if !categories.isEmpty { FolioCLI.say(String(localized: .courseShowCategories(categories.joined(separator: ", ")))) }
        if x.reviews == false { FolioCLI.say(String(localized: .courseShowReviewsOff)) }
        if !x.schedule.isEmpty {
            FolioCLI.say(String(localized: .courseShowSchedule))
            for t in x.schedule {
                let time = ClockText.range(t.startMinute, t.endMinute)
                FolioCLI.say("    \(ClassTime.weekdayNames[t.weekday - 1]) \(time) \(t.room)")
            }
        }
        if x.sharingApproved == true { FolioCLI.say(String(localized: .courseShowSharingApproved)) }
        if !x.memo.isEmpty { FolioCLI.say(String(localized: .courseShowMemo(x.memo))) }
    }
}
