import FolioActions
import FolioDomain
import Foundation

extension TodayShow: QueryOutput {
    func say(_ out: Summary, _ r: Resolver) throws {
        let now = r.ctx.now, calendar = r.ctx.calendar
        let tag = { (id: UUID) in (try? r.course(id: id).tag) }
        FolioCLI.say(
            (out.day.date(in: calendar) ?? now).formatted(
                .dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR"))
            ).styled(.bold)
                + "  " + (out.semester.folder?.name ?? "").styled(.dim))
        func section(_ title: String, _ items: [Item], time: Bool = true) {
            guard !items.isEmpty else { return }
            FolioCLI.say("")
            FolioCLI.say(title.styled(.bold, .cyan))
            let t = Table(
                header: ["", "", "", ""],
                rows: items.map { i in
                    let at = i.at.map { time ? when($0, now: now, time: true, calendar: calendar, settings: r.settings) : "" } ?? ""
                    let detail = i.detail.map { at.plain.hasPrefix($0) ? "" : $0 } ?? ""
                    return [tag(i.courseId) ?? i.course, i.title, at, detail.styled(.dim)]
                }, shrink: [1, 3])
            t.render().dropFirst().forEach { FolioCLI.say($0) }
        }
        if let o = out.ongoing { section(String(localized: .todaySectionOngoing), [o]) }
        section(String(localized: .todaySectionExams), out.exams)
        section(String(localized: .todaySectionClasses), out.classes)
        section(String(localized: .todaySectionReviewNotes), out.reviewNotes)
        section(String(localized: .todaySectionReviews), out.reviews, time: false)
        section(String(localized: .todaySectionDeferred), out.deferredReviews, time: false)
        section(String(localized: .todaySectionDeadlines), out.deadlines)
        section(String(localized: .todaySectionPlan), out.plan, time: false)
        section(String(localized: .todaySectionAttendance), out.attendance, time: false)
        section(String(localized: .todaySectionStudyTime), out.studyTime, time: false)
    }
}
