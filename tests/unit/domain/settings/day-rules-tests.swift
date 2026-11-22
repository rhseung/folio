import FolioCore
import Foundation
import PropertyBased
import Testing

@testable import FolioDomain

struct DayRulesTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    // 하루 경계(새벽 4시) 직전은 전날, 직후는 그날이다.
    @Test func nextDayStartsAtTheBoundary() throws {
        let settings = Settings()
        #expect(settings.nextDayStart(after: at(14, 3, 59), calendar: calendar) == at(14, 4))
        #expect(settings.nextDayStart(after: at(14, 4), calendar: calendar) == at(15, 4))
        #expect(settings.start(of: try #require(LocalDate(year: 2026, month: 11, day: 14)), calendar: calendar) == at(14, 4))
    }

    @Test func dueCountsStudyDaysAcrossTheBoundary() {
        let settings = Settings()
        let due = at(15, 3, 30)
        #expect(DateTimeText.days(due, from: at(14, 3, 59), settings: settings, calendar: calendar) == 1)
        #expect(DateTimeText.days(due, from: at(14, 4), settings: settings, calendar: calendar) == 0)
        #expect(DueUrgency(due: due, now: at(14, 4), settings: settings, calendar: calendar) == .urgent)
        #expect(DueUrgency(due: at(20, 23), now: at(14, 4), settings: settings, calendar: calendar) == .soon)
        #expect(DueUrgency(due: at(21, 23), now: at(14, 4), settings: settings, calendar: calendar) == .later)
    }

    @Test func urgencyFollowsTheSettings() {
        var urgency = UrgencySettings()
        #expect(DueUrgency(studyDays: 1, settings: urgency) == .urgent)
        #expect(DueUrgency(studyDays: 2, settings: urgency) == .soon)
        #expect(DueUrgency(studyDays: 7, settings: urgency) == .later)
        urgency.assignmentUrgentDays = 2
        #expect(DueUrgency(studyDays: 2, settings: urgency) == .urgent)

        let exam = UrgencySettings()
        #expect(ExamUrgency(days: 3, settings: exam) == .urgent)
        #expect(ExamUrgency(days: 4, settings: exam) == .soon)
        #expect(ExamUrgency(days: 7, settings: exam) == .soon)
        #expect(ExamUrgency(days: 8, settings: exam) == .near)
        #expect(ExamUrgency(days: 14, settings: exam) == .near)
        #expect(ExamUrgency(days: 15, settings: exam) == .later)
    }

    @Test func ddayText() {
        #expect(DateTimeText.dday(days: 0) == "D-day")
        #expect(DateTimeText.dday(days: 3) == "D-3")
        #expect(DateTimeText.dday(days: -2) == "D-0")
    }

    @Test func aDateReadsAsADayWordThenAWeekdayThenADate() {
        let read = { (date: Date) in DateTimeText.text(date, from: at(14, 12), settings: Settings(), calendar: calendar) }
        #expect(read(at(14, 23)) == "오늘")
        // 15일 새벽 2시는 하루 경계 전이라 14일의 공부일이다.
        #expect(read(at(15, 2)) == "오늘")
        #expect(read(at(15, 9)) == "내일")
        #expect(read(at(13, 9)) == "어제")
        #expect(read(at(16, 9)) == "월요일")
        #expect(read(at(20, 9)) == "금요일")
        #expect(read(at(21, 9)) == "11/21(토)")
        #expect(read(at(8, 9)) == "일요일")
        #expect(read(at(7, 9)) == "11/7(토)")
    }

    @Test func withTheClockTodayIsOnlyTheClockAndTheLastHourCountsMinutes() {
        let h12 = Locale(identifier: "ko_KR@hours=h12")
        let read = { (date: Date) in
            DateTimeText.text(date, from: at(14, 12), time: true, settings: Settings(), calendar: calendar, locale: h12)
        }
        #expect(read(at(14, 18)) == "오후 6:00")
        #expect(read(at(14, 13)) == "오후 1:00")
        #expect(read(at(14, 12, 45)) == "45분 뒤")
        #expect(read(at(14, 11, 1)) == "59분 전")
        #expect(read(at(14, 12)) == "지금")
        #expect(read(at(15, 23, 59)) == "내일 오후 11:59")
        #expect(read(at(17, 9)) == "화요일 오전 9:00")
        #expect(read(at(30, 9)) == "11/30(월) 오전 9:00")
        // 12시간제와 24시간제는 로케일(Mac의 시각 설정)을 따른다.
        let h23 = Locale(identifier: "ko_KR@hours=h23")
        #expect(
            DateTimeText.text(at(15, 23, 59), from: at(14, 12), time: true, settings: Settings(), calendar: calendar, locale: h23)
                == "내일 23:59")
    }

    @Test func anAllDayDateCountsCalendarDaysAndHasNoClock() {
        let now = at(14, 12)
        // 종일 일정의 15일 자정은 하루 경계 앞이지만 15일이다. 시각을 쓰라고 해도 자정은 쓰지 않는다.
        #expect(DateTimeText.days(at(15, 0), from: now, settings: Settings(), calendar: calendar) == 1)
        #expect(DateTimeText.text(at(15, 0), from: now, time: true, settings: Settings(), calendar: calendar) == "내일")
        #expect(DateTimeText.text(at(14, 0), from: now, time: true, settings: Settings(), calendar: calendar) == "오늘")
    }

    @Test func anExamWithoutATimeShowsOnlyItsDate() {
        let ko = Locale(identifier: "ko_KR@hours=h12")
        let dateOnly = DateTimeText.date(at(15, 0), calendar: calendar, locale: ko)
        let timed = DateTimeText.date(at(15, 9), calendar: calendar, locale: ko)
        #expect(!dateOnly.contains("12:00") && !dateOnly.contains("오전"))
        #expect(timed.hasPrefix(dateOnly) && timed.contains("9:00"))
    }

    @Test func theMinuteCountStopsExactlyAtAnHour() async {
        await propertyCheck(input: Gen.int(in: -10_000...10_000)) { seconds in
            let now = Date(timeIntervalSince1970: 1_794_800_000)
            #expect((DateTimeText.soon(now + TimeInterval(seconds), from: now) == nil) == (abs(seconds) >= 3600))
        }
    }

    @Test func nextClassSkipsCancelledAndPastClasses() {
        let now = at(14, 12)
        let past = Session(device: device, at: now, week: 10, date: at(13, 10))
        var cancelled = Session(device: device, at: now, week: 10, date: at(16, 10))
        cancelled.kind = .cancelled
        let later = Session(device: device, at: now, week: 11, date: at(18, 10))
        let file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"), sessions: [past, cancelled, later])

        #expect(file.heldSessions(at: now).map(\.id) == [past.id])
        #expect(file.nextClass(after: now, suggested: [])?.session?.id == later.id)
        let planned = file.nextClass(after: now, suggested: [at(17, 10), at(12, 10)])
        #expect(planned?.date == at(17, 10))
        #expect(planned?.session == nil)
        #expect(CourseFile(course: Course(device: device, at: now, title: "물리")).nextClass(after: now, suggested: []) == nil)
    }

    @Test func scheduleDefaultsComeFromSettings() {
        var settings = Settings()
        #expect(
            settings.schedule.due(on: at(20, 9), calendar: calendar)
                == calendar.date(bySettingHour: 23, minute: 59, second: 0, of: at(20, 9)))
        settings.schedule.dueMinute = 18 * 60
        #expect(settings.schedule.due(on: at(20, 9), calendar: calendar) == at(20, 18))
        #expect(settings.schedule.examEndMinute(startMinute: 9 * 60) == 11 * 60)
    }

    @Test func nextTermFollowsTheNewest() {
        let now = at(14, 12)
        #expect(Term.next(after: nil, now: now, calendar: calendar) == (2026, .fall))
        #expect(Term.next(after: (2026, .spring), now: now, calendar: calendar) == (2026, .summer))
        #expect(Term.next(after: (2026, .winter), now: now, calendar: calendar) == (2027, .spring))
    }

    @Test func clockText() {
        #expect(ClockText.duration(65) == "1:05")
        #expect(ClockText.duration(3725) == "1:02:05")
        #expect(ClockText.duration(65, hours: true) == "0:01:05")
        #expect(ClockText.minute(9 * 60 + 5) == "09:05")
        #expect(ClockText.range(630, 765) == "10:30–12:45")
        #expect(calendar.minuteOfDay(at(14, 10, 30)) == 630)
        #expect(calendar.date(atMinute: 630, of: at(14, 0)) == at(14, 10, 30))
    }

    @Test func lmsSyncWaitsForTheInterval() {
        var lms = LMSSettings()
        let now = at(14, 12)
        #expect(lms.syncDue(lastAttempt: nil, now: now))
        #expect(!lms.syncDue(lastAttempt: now.addingTimeInterval(-29 * 60), now: now))
        #expect(lms.syncDue(lastAttempt: now.addingTimeInterval(-30 * 60), now: now))
        lms.syncMinutes = 60
        #expect(!lms.syncDue(lastAttempt: now.addingTimeInterval(-30 * 60), now: now))
    }
}
