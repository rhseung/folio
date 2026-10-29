@testable import FolioDomain
import Foundation
import Testing

/// Shapes from the 2026 fall calendar: sessions imported from Notion carry only a day.
struct CalendarImportTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func lecture(_ day: Int) -> CalendarMeeting {
        CalendarMeeting(course: "GS2004 선형대수학", start: at(day, 14, 30), end: at(day, 15, 45), room: "A229")
    }

    @Test func fillsKnownDaysAndAddsTheRest() {
        var existing = Session(device: device, at: now, week: 2, index: 1, date: calendar.startOfDay(for: at(8, 0)))
        existing.topic = "Vectors"
        let file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"), sessions: [existing])
        let recitation = CalendarMeeting(course: "GS2004 선형대수학", start: at(8, 18, 30), end: at(8, 19, 30), room: "C110")
        let meetings = [lecture(8), lecture(10), recitation, lecture(15), lecture(17), lecture(22),
                        CalendarMeeting(course: "GS2004 선형대수학", start: at(23, 21), end: at(23, 22, 15))]
        let start = LocalDate(year: 2026, month: 8, day: 31)!
        let r = CalendarImporter.merge(meetings, into: file, semesterStart: start, calendar: calendar, device: device, now: now)

        #expect(r.filled.map(\.id) == [existing.id])
        #expect(r.file.sessions.first { $0.id == existing.id }?.date == at(8, 14, 30))
        #expect(r.file.sessions.first { $0.id == existing.id }?.topic == "Vectors")
        // Week 2 keeps 2-1 for the day's first meeting; the recitation that evening is a session of its own.
        #expect(r.added.filter { $0.week == 2 }.map { [$0.date, Double($0.index)] as [AnyHashable] } == [[at(8, 18, 30), 2.0], [at(10, 14, 30), 3.0]])
        #expect(r.added.filter { $0.week == 4 }.map(\.date) == [at(22, 14, 30), at(23, 21)])
        #expect(r.file.course.schedule.map(\.weekday) == [2])
        #expect(r.cancelled.isEmpty)

        let again = CalendarImporter.merge(meetings, into: r.file, semesterStart: start, calendar: calendar, device: device, now: now)
        #expect(again.added.isEmpty && again.filled.isEmpty)
    }

    @Test func linksNotesNamedAfterTopics() {
        var lab = Session(device: device, at: now, week: 3, index: 1, date: at(16, 10, 30))
        lab.topic = "Accuracy & Precision"
        let taken = UUID(), free = UUID()
        let links = CalendarImporter.noteLinks(sessions: [lab], notes: [
            (taken, "Accuracy & Precision", UUID()), (free, "Accuracy & Precision", nil),
        ])
        #expect(links.map(\.note) == [free])
    }

    /// A day the calendar skips inside its span is a cancelled class; the session stays, marked.
    @Test func sessionsOnSkippedDaysAreCancelled() {
        let holiday = Session(device: device, at: now, week: 6, index: 1, date: calendar.startOfDay(for: at(5, 0, month: 10)))
        let late = Session(device: device, at: now, week: 16, index: 1, date: at(14, 14, 30, month: 12))
        let file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"), sessions: [holiday, late])
        var after = lecture(7)
        after.start = at(7, 14, 30, month: 10)
        // The calendar spans 9/8 to 10/7: 10/5 falls inside with no meeting, 12/14 is past its end.
        let r = CalendarImporter.merge([lecture(8), after], into: file, semesterStart: LocalDate(year: 2026, month: 8, day: 31)!,
                                       calendar: calendar, device: device, now: now)
        #expect(r.cancelled.map(\.id) == [holiday.id])
        #expect(r.file.sessions.first { $0.id == late.id }?.isCancelled == false)
    }

    /// 선형대수학 had a Notion midterm without an end; graph theory had none. A final on another day stays a conflict.
    @Test func examsFillTheSameDayAndAddMissingOnes() {
        var midterm = Exam(device: device, at: now, kind: .midterm, title: "Midterm", start: at(20, 20, month: 10), location: "C104")
        midterm.memo = ""
        let final = Exam(device: device, at: now, kind: .final, title: "Final", start: at(14, 9, month: 12))
        let file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"), exams: [midterm, final])
        let exams = [
            CalendarExam(course: "", kind: .midterm, start: at(20, 20, month: 10), end: at(20, 22, 45, month: 10), location: "C 104", memo: "자리배치표대로 앉기"),
            CalendarExam(course: "", kind: .final, start: at(16, 9, month: 12), end: at(16, 11, month: 12)),
            CalendarExam(course: "", kind: .quiz, start: at(1, 9, month: 10), end: at(1, 10, month: 10)),
        ]
        let r = CalendarImporter.mergeExams(exams, into: file, calendar: calendar, device: device, now: now)
        let m = r.file.exams.first { $0.id == midterm.id }!
        #expect(m.end == at(20, 22, 45, month: 10) && m.location == "C104" && m.memo == "자리배치표대로 앉기")
        #expect(r.added.map(\.title) == ["Quiz1"])
        #expect(r.conflicts.map(\.exam.id) == [final.id])
        #expect(CalendarImporter.mergeExams(exams, into: r.file, calendar: calendar, device: device, now: now).added.isEmpty)
    }
}

struct LabUnitTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aLabIsAUnitTitledByItsNumber() {
        let unit = { (t: String) in Unit(device: device, at: now, title: t, order: 0) }
        #expect(unit("Lab04 Thin-layer chromatography").labNumber == 4)
        #expect(unit("lab 12: Titration").labTitle == "Titration")
        #expect(unit("Labeling").labNumber == nil && unit("1장 Lab04").labNumber == nil)
    }

    /// The parts of a two-session experiment share one unit; a meeting without a number links nothing.
    @Test func calendarLabMeetingsLinkToTheirUnit() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day = { (d: Int) in c.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 10))! }
        let meet = { (d: Int, lab: Int?) in CalendarMeeting(course: "GS1211 일반화학실험", start: day(d), end: day(d) + 7200, topic: "TLC", lab: lab) }
        let file = CourseFile(course: Course(device: device, at: now, title: "일반화학실험"))
        let r = CalendarImporter.merge([meet(15, 4), meet(17, 4), meet(22, nil)], into: file, semesterStart: LocalDate("2026-08-31")!,
                                       calendar: c, device: device, now: now)
        #expect(r.file.units.map(\.title) == ["Lab04 TLC"])
        #expect(r.file.units[0].sessionIds == r.file.sessions.prefix(2).map(\.id))
        #expect(r.file.sessions[2].unitIds.isEmpty)
        let again = CalendarImporter.merge([meet(15, 4), meet(17, 4), meet(22, nil)], into: r.file, semesterStart: LocalDate("2026-08-31")!,
                                           calendar: c, device: device, now: now)
        #expect(again.added.isEmpty && again.filled.isEmpty && again.file.units == r.file.units)
    }
}
