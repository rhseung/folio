import FolioActions
import FolioDomain
import Foundation

extension CourseList: QueryLines {
    func lines(_ courses: [Course], _ r: Resolver) throws -> [[String]] {
        try courses.map { x in
            [try r.course(id: x.id).code, x.title, String(localized: .courseListCredits(x.credits.formatted()))]
        }
    }

    func say(_ courses: [Course], _ r: Resolver) throws {
        let catalog = try? r.ctx.catalog()
        var t = Table(
            header: [
                "", String(localized: .courseListHeaderCode), String(localized: .courseListHeaderCourse),
                String(localized: .courseListHeaderCredits), String(localized: .courseListHeaderMode),
                String(localized: .courseListHeaderGrade),
            ], shrink: [2])
        for x in courses {
            let c = try r.course(id: x.id)
            t.rows.append([
                "●".course(c.color), c.tag, x.title, x.credits.formatted(), x.gradingMode.rawValue.toned(x.gradingMode.tone),
                catalog?.grade(x.finalGrade).map { GradesLock.masked($0.symbol) } ?? "",
            ])
        }
        t.print()
        footer(courses.count, hidden: all ? nil : String(localized: .courseListHiddenAll))
    }
}
