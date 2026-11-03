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

    func session(_ week: Int, _ s: String) -> Session {
        Session(device: device, at: .now, week: week, date: date(s))
    }

    func kinds(_ items: [SessionTimeline.Item], in file: CourseFile) -> [String] {
        items.map {
            switch $0 {
            case .week(let s, let month): "week\(s[0].week)" + (month == nil ? "" : "+m")
            case .month: "month"
            case .exam(let e, _): e.title
            case .session(let s, let exams): "s" + file.name(of: s).replacing("주차", with: "") + exams.map { "+" + $0.title }.joined()
            case .planned(let s, let exams): "p\(s.week)" + exams.map { "+" + $0.title }.joined()
            }
        }
    }

    /// Week 10 holds Fri 10/30 and Mon 11/2, so November begins partway through it and gets a line of its own.
    @Test func groupsByWeekInDateOrderAndMarksMonthTurns() {
        let file = CourseFile(course: Course(device: device, at: .now, title: ""), sessions: [
            session(10, "2026-11-02 13:00"), session(9, "2026-10-26 13:00"), session(10, "2026-10-30 13:00"),
        ])
        #expect(kinds(SessionTimeline.items(file, classMinutes: 75, calendar: calendar), in: file) == ["week9+m", "s9-1", "week10", "s10-1", "month", "s10-2"])
    }

    /// Exams outside class time sit by date inside their week, or between weeks when no class shares the week.
    @Test func examsOutsideClassTakeTheirOwnRows() {
        let midterm = Exam(device: device, at: .now, title: "중간", start: date("2026-10-21 09:00"))
        let final = Exam(device: device, at: .now, title: "기말", start: date("2026-12-14 09:00"))
        let quiz = Exam(device: device, at: .now, title: "퀴즈", start: date("2026-10-27 09:00"))
        let undated = Exam(device: device, at: .now, title: "미정")
        let file = CourseFile(course: Course(device: device, at: .now, title: ""),
                              sessions: [session(8, "2026-10-19 13:00"), session(9, "2026-10-26 13:00")],
                              exams: [final, quiz, midterm, undated])
        #expect(kinds(SessionTimeline.items(file, classMinutes: 75, calendar: calendar), in: file)
            == ["week8+m", "s8-1", "중간", "week9", "s9-1", "퀴즈", "기말"])
    }

    /// Only the times decide: an exam inside a held or planned class rides on it, one in a cancelled class stands alone.
    @Test func examsDuringClassRideOnThatClass() {
        let held = session(9, "2026-10-26 13:00")
        var cancelled = session(9, "2026-10-28 13:00")
        cancelled.isCancelled = true
        let planned = session(10, "2026-11-02 13:00")
        let exams = [
            Exam(device: device, at: .now, title: "퀴즈1", start: date("2026-10-26 14:00"), end: date("2026-10-26 14:15")),
            Exam(device: device, at: .now, title: "퀴즈2", start: date("2026-10-28 13:00")),
            Exam(device: device, at: .now, title: "퀴즈3", start: date("2026-11-02 12:30"), end: date("2026-11-02 13:10")),
            Exam(device: device, at: .now, title: "끝난 뒤", start: date("2026-11-02 14:15")),
        ]
        let file = CourseFile(course: Course(device: device, at: .now, title: ""), sessions: [held, cancelled], exams: exams)
        #expect(kinds(SessionTimeline.items(file, planned: [planned], classMinutes: 75, calendar: calendar), in: file)
            == ["week9+m", "s9-1+퀴즈1", "s9-2", "퀴즈2", "week10+m", "p10+퀴즈3", "끝난 뒤"])
    }

    @Test func heldFromTheItemsOwnDate() {
        let s = session(9, "2026-10-26 13:00")
        #expect(SessionTimeline.Item.session(s, exams: []).held(at: date("2026-10-26 13:00")))
        #expect(!SessionTimeline.Item.week([s], month: nil).held(at: date("2026-10-26 12:59")))
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
