import FolioDomain
import Foundation
import Testing

struct SessionCountsTests {
    let device = UUID()
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s) ?? .distantPast
    }

    func session(_ week: Int, _ s: String) -> Session {
        Session(device: device, at: .now, week: week, date: date(s))
    }

    @Test func countsMissingReviewNotesAndUnlinkedClasses() {
        let now = date("2026-10-28 12:00")
        var reviewed = session(9, "2026-10-26 13:00")
        reviewed.reviewNoteId = UUID()
        let owing = session(8, "2026-10-19 13:00")
        var skipped = session(8, "2026-10-21 13:00")
        skipped.skipsReview = true
        let ahead = session(9, "2026-10-28 13:00")
        var file = CourseFile(course: Course(device: device, at: .now, title: ""), sessions: [reviewed, owing, skipped, ahead])

        #expect(file.missingReviewNotes(at: now) == 1)

        #expect(file.sessionsNeedingUnits(at: now).isEmpty)

        var unit = Unit(device: device, at: .now, title: "그래프", order: 1)
        unit.sessionIds = [reviewed.id]
        file.units = [unit]
        #expect(file.sessionsNeedingUnits(at: now).map(\.id) == [owing.id])
        file.course.reviews = false
        #expect(file.missingReviewNotes(at: now) == 0)
    }

    @Test func remainingClassesCountSavedAndPlannedButNotCancelled() {
        let now = date("2026-10-28 12:00")
        let past = session(9, "2026-10-26 13:00")
        let absent = session(9, "2026-10-28 13:00")
        var cancelled = session(10, "2026-11-02 13:00")
        cancelled.isCancelled = true
        let makeup = session(10, "2026-11-03 18:00")
        let file = CourseFile(course: Course(device: device, at: .now, title: ""), sessions: [past, absent, cancelled, makeup])
        let planned = [session(10, "2026-11-04 13:00"), session(11, "2026-11-09 13:00")]

        #expect(file.remainingClasses(after: now, planned: planned) == 4)
        #expect(file.remainingClasses(after: now, planned: []) == 2)
    }
}
