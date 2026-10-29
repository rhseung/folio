import FolioDomain
import Foundation
import Testing

struct SessionTimelineTests {
    let device = UUID()
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    func session(_ week: Int, _ index: Int, _ s: String) -> Session {
        Session(device: device, at: .now, week: week, index: index, date: date(s))
    }

    func kinds(_ items: [SessionTimeline.Item]) -> [String] {
        items.map {
            switch $0 {
            case .week(let s, let month): "week\(s[0].week)" + (month == nil ? "" : "+m")
            case .month: "month"
            case .exam(let e, _): e.title
            case .session(let s): "s\(s.week)-\(s.index)"
            }
        }
    }

    /// Week 10 holds Fri 10/30 and Mon 11/2, so November begins partway through it and gets a line of its own.
    @Test func groupsByWeekInDateOrderAndMarksMonthTurns() {
        let file = CourseFile(course: Course(device: device, at: .now, title: ""), sessions: [
            session(10, 2, "2026-11-02 13:00"), session(9, 1, "2026-10-26 13:00"), session(10, 1, "2026-10-30 13:00"),
        ])
        #expect(kinds(SessionTimeline.items(file, calendar: calendar)) == ["week9+m", "s9-1", "week10", "s10-1", "month", "s10-2"])
    }

    @Test func midtermAndFinalFallBetweenWeeksAndQuizzesAreLeftOut() {
        let midterm = Exam(device: device, at: .now, kind: .midterm, title: "중간", start: date("2026-10-21 09:00"))
        let final = Exam(device: device, at: .now, kind: .final, title: "기말", start: date("2026-12-14 09:00"))
        let quiz = Exam(device: device, at: .now, kind: .quiz, title: "퀴즈", start: date("2026-10-27 09:00"))
        let undated = Exam(device: device, at: .now, kind: .final, title: "미정")
        let file = CourseFile(course: Course(device: device, at: .now, title: ""),
                              sessions: [session(8, 1, "2026-10-19 13:00"), session(9, 1, "2026-10-26 13:00")],
                              exams: [final, quiz, midterm, undated])
        #expect(kinds(SessionTimeline.items(file, calendar: calendar)) == ["week8+m", "s8-1", "중간", "week9", "s9-1", "기말"])
    }

    @Test func heldFromTheItemsOwnDate() {
        let s = session(9, 1, "2026-10-26 13:00")
        #expect(SessionTimeline.Item.session(s).held(at: date("2026-10-26 13:00")))
        #expect(!SessionTimeline.Item.week([s], month: nil).held(at: date("2026-10-26 12:59")))
    }

    @Test func countsMissingReviewNotesAndUnlinkedClasses() {
        let now = date("2026-10-28 12:00")
        var reviewed = session(9, 1, "2026-10-26 13:00")
        reviewed.reviewNoteId = UUID()
        let owing = session(8, 1, "2026-10-19 13:00")
        var skipped = session(8, 2, "2026-10-21 13:00")
        skipped.skipsReview = true
        let ahead = session(9, 2, "2026-10-28 13:00")
        var file = CourseFile(course: Course(device: device, at: .now, title: ""), sessions: [reviewed, owing, skipped, ahead])
        #expect(file.missingReviewNotes(at: now) == 1)
        // Nothing to link to yet, so nothing is flagged.
        #expect(file.sessionsNeedingUnits(at: now).isEmpty)
        var unit = Unit(device: device, at: .now, title: "그래프", order: 1)
        unit.sessionIds = [reviewed.id]
        file.units = [unit]
        #expect(file.sessionsNeedingUnits(at: now).map(\.id) == [owing.id])
        file.course.reviews = false
        #expect(file.missingReviewNotes(at: now) == 0)
    }
}
