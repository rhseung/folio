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
            case .session(let s, let exams): "s" + file.reference(of: s, calendar: calendar) + exams.map { "+" + $0.title }.joined()
            case .planned(let s, let exams): "p\(s.week)" + exams.map { "+" + $0.title }.joined()
            }
        }
    }

    // 10주차에는 10/30 금요일과 11/2 월요일이 있으므로, 11월이 주 중간에 시작해 따로 줄을 받는다.
    @Test func groupsByWeekInDateOrderAndMarksMonthTurns() {
        let file = CourseFile(
            course: Course(device: device, at: .now, title: ""),
            sessions: [
                session(10, "2026-11-02 13:00"), session(9, "2026-10-26 13:00"), session(10, "2026-10-30 13:00"),
            ])
        #expect(
            kinds(SessionTimeline.items(file, classMinutes: 75, calendar: calendar), in: file) == [
                "week9+m", "s10-26", "week10", "s10-30", "month", "s11-02",
            ])
    }

    @Test func examsOutsideClassTakeTheirOwnRows() {
        let midterm = Exam(device: device, at: .now, title: "중간", start: date("2026-10-21 09:00"))
        let final = Exam(device: device, at: .now, title: "기말", start: date("2026-12-14 09:00"))
        let quiz = Exam(device: device, at: .now, title: "퀴즈", start: date("2026-10-27 09:00"))
        let undated = Exam(device: device, at: .now, title: "미정")
        let file = CourseFile(
            course: Course(device: device, at: .now, title: ""),
            sessions: [session(8, "2026-10-19 13:00"), session(9, "2026-10-26 13:00")],
            exams: [final, quiz, midterm, undated])
        #expect(
            kinds(SessionTimeline.items(file, classMinutes: 75, calendar: calendar), in: file)
                == ["week8+m", "s10-19", "중간", "week9", "s10-26", "퀴즈", "기말"])
    }

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

        #expect(
            kinds(SessionTimeline.items(file, planned: [planned], classMinutes: 75, calendar: calendar), in: file)
                == ["week9+m", "s10-26+퀴즈1", "s10-28", "퀴즈2", "week10+m", "p10+퀴즈3", "끝난 뒤"])
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
