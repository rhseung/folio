import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct SessionTableTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()
    let settings = Settings()
    let monWed = [
        ClassTime(weekday: 1, startMinute: 540, endMinute: 615, room: "A101"), ClassTime(weekday: 3, startMinute: 540, endMinute: 615),
    ]

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s) ?? .distantPast
    }

    func day(_ s: String) -> LocalDate { LocalDate(s) ?? LocalDate(.distantPast, in: calendar) }

    func session(_ s: String, kind: Session.Kind = .lecture, wrapped: Bool = true) -> Session {
        var session = Session(device: device, at: .now, week: 1, date: date(s))
        session.kind = kind
        session.isWrappedUp = wrapped
        return session
    }

    func file(_ sessions: [Session] = [], schedule: [ClassTime]? = nil, exams: [Exam] = [], assignments: [Assignment] = []) -> CourseFile {
        CourseFile(
            course: Course(device: device, at: .now, title: "그래프 이론", schedule: schedule ?? monWed), sessions: sessions, exams: exams,
            assignments: assignments)
    }

    func semester(_ start: String, _ end: String) -> Semester {
        Semester(device: device, at: .now, year: 2026, term: .fall, start: day(start), end: day(end))
    }

    func names(_ cell: SessionTable.Cell) -> [String] {
        cell.entries.map { e in
            switch e.item {
            case .session(let s): "s" + LocalDate(s.date, in: calendar).description.suffix(5)
            case .planned(let s): "p" + LocalDate(s.date, in: calendar).description.suffix(5)
            case .exam(let x): x.title
            case .deadline(let a): a.title
            }
        }
    }

    @Test func columnsAreTheClassWeekdaysInOrder() {
        let schedule = [
            ClassTime(weekday: 5, startMinute: 780, endMinute: 830), ClassTime(weekday: 1, startMinute: 780, endMinute: 830),
            ClassTime(weekday: 2, startMinute: 780, endMinute: 830), ClassTime(weekday: 4, startMinute: 780, endMinute: 830),
            ClassTime(weekday: 1, startMinute: 600, endMinute: 650),
        ]
        let table = SessionTable(file(schedule: schedule), now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        #expect(table.columns.map(\.weekday) == [1, 2, 4, 5])
        // 같은 요일의 두 수업은 열 하나를 나눈다.
        #expect(table.columns[0].slots.map(\.startMinute) == [600, 780])
    }

    @Test func rowsRunMondayToSundayThroughTheSemester() throws {
        var term = semester("2026-09-01", "2026-12-19")
        term.midtermWeek = 8
        term.finalWeek = 15
        let table = SessionTable(
            file([session("2026-11-02 09:00")]), semester: term, now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        #expect(table.weeks.first?.start == day("2026-08-31"))
        #expect(table.weeks.last?.start == day("2026-12-14"))
        #expect(table.weeks.map(\.number) == Array(1...16))
        #expect(table.weeks.filter(\.isExamWeek).map(\.number) == [8, 15])
        let now = table.weeks.filter(\.isThisWeek)
        #expect(now.map(\.number) == [10])
        #expect(now.first?.end == day("2026-11-08"))
        let session = try #require(table.weeks[9].cells[0].entries[0].session)
        #expect(table.week(containing: session.id) == day("2026-11-02"))
    }

    @Test func classDaysTakeTheirColumnAndTheRestGoesToTheOtherCell() {
        let midterm = Exam(device: device, at: .now, title: "중간고사", start: date("2026-10-22 19:00"), location: "B203")
        let hw = Assignment(device: device, at: .now, title: "HW2", due: date("2026-10-23 23:59"))
        let onClassDay = Assignment(device: device, at: .now, title: "HW3", due: date("2026-10-21 23:59"))
        let table = SessionTable(
            file(
                [
                    session("2026-10-19 09:00"), session("2026-10-21 09:00"), session("2026-10-21 18:00", kind: .makeup),
                    session("2026-10-24 10:00", kind: .makeup),
                ], exams: [midterm], assignments: [hw, onClassDay]),
            now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        let week = table.weeks[0]
        #expect(week.cells.map(\.weekday) == [1, 3, nil])
        #expect(names(week.cells[0]) == ["s10-19"])
        // 같은 날 수업과 보강은 그 요일 칸에 쌓는다.
        #expect(names(week.cells[1]) == ["s10-21", "s10-21", "HW3"])
        #expect(names(week.other) == ["중간고사", "HW2", "s10-24"])
        #expect(week.cells[1].entries[1].isMakeup && week.cells[1].entries[1].offSchedule)
        #expect(!week.cells[1].entries[0].offSchedule)
    }

    @Test func fourClassDaysGiveFourColumnsAndTheOtherCell() {
        let schedule = [1, 2, 4, 5].map { ClassTime(weekday: $0, startMinute: 780, endMinute: 830) }
        let sessions = ["2026-10-26 13:00", "2026-10-27 13:00", "2026-10-29 13:00", "2026-10-30 13:00", "2026-10-28 13:00"].map {
            session($0)
        }
        let table = SessionTable(file(sessions, schedule: schedule), now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        #expect(table.weeks.count == 1)
        #expect(table.weeks[0].cells.map { $0.entries.count } == [1, 1, 1, 1, 1])
        #expect(table.weeks[0].other.entries.first?.day == day("2026-10-28"))
    }

    // 하루 경계는 새벽 4시다. 월요일 3:59는 아직 일요일이라 지난주가 이번 주다.
    @Test func thisWeekAndTodayFollowTheStudyDay() {
        let f = file([session("2026-10-26 09:00"), session("2026-11-02 09:00")])
        let before = SessionTable(f, now: date("2026-11-02 03:59"), settings: settings, calendar: calendar)
        #expect(before.thisWeek == day("2026-10-26"))
        #expect(before.weeks.first { $0.isThisWeek }?.start == day("2026-10-26"))
        #expect(!before.weeks[1].cells[0].isToday)

        let after = SessionTable(f, now: date("2026-11-02 04:00"), settings: settings, calendar: calendar)
        #expect(after.thisWeek == day("2026-11-02"))
        #expect(after.weeks[1].isThisWeek && after.weeks[1].cells[0].isToday)
        #expect(after.weeks[1].agenda.first?.isToday == true)
    }

    @Test func aWeekAcrossTwoMonthsMarksTheFirstDayOfTheLaterMonth() {
        let hw = Assignment(device: device, at: .now, title: "HW", due: date("2026-11-01 23:59"))
        let table = SessionTable(
            file([session("2026-10-26 09:00"), session("2026-10-28 09:00"), session("2026-11-02 09:00")], assignments: [hw]),
            now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        #expect(table.weeks[0].agenda.map(\.day) == [day("2026-10-26"), day("2026-10-28"), day("2026-11-01")])
        #expect(table.weeks[0].agenda.map(\.month) == [nil, nil, 11])
        // 한 달 안의 주에는 붙이지 않는다.
        #expect(table.weeks[1].agenda.map(\.month) == [nil])
    }

    @Test func blocksTakeTheirLookAndTags() {
        var late = session("2026-10-19 09:00")
        late.reviewNoteId = UUID()
        let absent = session("2026-10-21 09:00")
        let unwrapped = session("2026-11-04 09:00", wrapped: false)
        let cancelled = session("2026-10-26 09:00", kind: .cancelled)
        var f = file([late, absent, unwrapped, cancelled])
        f.attendance = [
            Attendance(device: device, at: .now, sessionId: late.id, state: .late),
            Attendance(device: device, at: .now, sessionId: absent.id, state: .absent),
        ]
        f.recordings = [Recording(device: device, at: .now, sessionId: late.id, file: "Recordings/a.m4a", duration: 4500)]
        let table = SessionTable(f, now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        let all = table.weeks.flatMap(\.cells).flatMap(\.entries)
        func entry(_ s: Session) -> SessionTableEntry? { all.first { $0.session?.id == s.id } }

        #expect(entry(late)?.look == .late)
        #expect(entry(late)?.tags == [.attendance(.late), .recording(4500), .reviewNote])
        #expect(entry(absent)?.look == .absent)
        #expect(entry(absent)?.tags == [.attendance(.absent), .noReviewNote])
        #expect(entry(unwrapped)?.tags == [.unwrapped, .noReviewNote])
        #expect(entry(cancelled)?.look == .cancelled && entry(cancelled)?.tags == [.cancelled])

        let elsewhere = SessionTable(f, now: date("2026-11-04 11:20"), settings: settings, asksWrapUp: false, calendar: calendar)
        #expect(!elsewhere.weeks.flatMap(\.cells).flatMap(\.entries).contains { $0.tags.contains(.unwrapped) })
    }

    @Test func theNextClassIsTheFirstFutureOneAndPlannedClassesGiveWayToSavedOnes() throws {
        let saved = session("2026-11-09 09:00")
        let planned = [session("2026-11-09 09:00"), session("2026-11-11 09:00")]
        let cancelled = session("2026-11-05 09:00", kind: .cancelled)
        let table = SessionTable(
            file([saved, cancelled]), planned: planned, now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        let week = try #require(table.weeks.first { $0.start == day("2026-11-09") })
        #expect(names(week.cells[0]) == ["s11-09"])
        #expect(week.cells[0].entries[0].look == .next)
        #expect(names(week.cells[1]) == ["p11-11"])
        #expect(week.cells[1].entries[0].look == .upcoming && week.cells[1].entries[0].tags.isEmpty)
    }

    @Test func deadlinesStrikeThroughOncePastOrHandedIn() {
        var handedIn = Assignment(device: device, at: .now, title: "HW4", due: date("2026-11-06 23:59"))
        handedIn.set(.submitted, now: date("2026-11-03 10:00"))
        let past = Assignment(device: device, at: .now, title: "HW2", due: date("2026-10-30 23:59"))
        let open = Assignment(device: device, at: .now, title: "HW5", due: date("2026-11-13 23:59"))
        let table = SessionTable(
            file(assignments: [handedIn, past, open]), now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        let looks = Dictionary(
            uniqueKeysWithValues: table.weeks.flatMap(\.cells).flatMap(\.entries).map { ($0.subject ?? "", $0.look) })
        #expect(looks == ["HW4": .deadlineClosed, "HW2": .deadlineClosed, "HW5": .deadline])
    }

    // 1월과 2월은 전해로 셈하는 보정, 윤년 2월 29일, 세기 윤년(2000)이 손으로 고른 예시다.
    @Test func weekdaysMatchTheCalendarOnHandPickedDays() {
        #expect(SessionTable.weekday(of: day("2026-11-02")) == 1)
        #expect(SessionTable.weekday(of: day("2026-11-08")) == 7)
        #expect(SessionTable.weekday(of: day("2024-02-29")) == 4)
        #expect(SessionTable.weekday(of: day("2027-01-01")) == 5)
        #expect(SessionTable.weekday(of: day("2000-03-01")) == 3)
        #expect(SessionTable.monday(of: day("2026-11-01")) == day("2026-10-26"))
    }

    @Test func weekdaysAndMondaysAgreeWithTheGregorianCalendar() async {
        let calendar = calendar
        await propertyCheck(input: Gen.int(in: 1900...2200), Gen.int(in: 1...12), Gen.int(in: 1...31)) { year, month, d in
            guard let day = LocalDate(year: year, month: month, day: d), let date = day.date(in: calendar) else { return }
            let iso = (calendar.component(.weekday, from: date) + 5) % 7 + 1
            #expect(SessionTable.weekday(of: day) == iso, "\(day)")
            let monday = SessionTable.monday(of: day)
            #expect(SessionTable.weekday(of: monday) == 1, "\(day)")
            #expect((0...6).contains(monday.days(until: day)), "\(day)")
        }
    }

    @Test func aCourseWithNothingDatedHasNoRows() {
        let table = SessionTable(file(), now: date("2026-11-04 11:20"), settings: settings, calendar: calendar)
        #expect(table.weeks.isEmpty)
        #expect(table.columns.count == 2)
    }
}
