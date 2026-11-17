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
        #expect(settings.studyDays(from: at(14, 3, 59), until: due, calendar: calendar) == 1)
        #expect(settings.studyDays(from: at(14, 4), until: due, calendar: calendar) == 0)
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
        #expect(DDay.text(0) == "D-day")
        #expect(DDay.text(3) == "D-3")
        #expect(DDay.text(-2) == "D-0")
    }

    @Test func relativeDaysReadAsWords() {
        #expect([-3, -1, 0, 1, 4].map(RelativeDay.text) == ["3일 전", "어제", "오늘", "내일", "4일 뒤"])
        #expect([6, 7, 13, 14, 29, 30, 59, 60].map(RelativeDay.text) == ["6일 뒤", "1주 뒤", "1주 뒤", "2주 뒤", "4주 뒤", "1달 뒤", "1달 뒤", "2달 뒤"])
        #expect([-6, -7, -29, -30, -95].map(RelativeDay.text) == ["6일 전", "1주 전", "4주 전", "1달 전", "3달 전"])
    }

    @Test func aDueWithinADayCountsHoursThenMinutes() {
        let now = Date(timeIntervalSince1970: 1_794_800_000)
        let read = { (seconds: TimeInterval) in RelativeTime.text(until: now + seconds, from: now) }
        #expect(read(24 * 3600) == nil)
        #expect(read(-24 * 3600) == nil)
        #expect(read(24 * 3600 - 1) == "23시간 뒤")
        #expect(read(-(3 * 3600 + 59 * 60)) == "3시간 전")
        #expect(read(3600) == "1시간 뒤")
        #expect(read(3600 - 1) == "59분 뒤")
        #expect(read(-(5 * 60 + 59)) == "5분 전")
        #expect(read(60) == "1분 뒤")
        #expect(read(59) == "지금")
        #expect(read(-59) == "지금")
    }

    @Test func aDueReadsInHoursWithinADayAndInStudyDaysBeyond() {
        let read = { (due: Date) in RelativeDay.text(until: due, from: at(14, 12), settings: Settings(), calendar: calendar) }
        #expect(read(at(14, 9)) == "3시간 전")
        // 하루가 넘으면 공부일로 센다. 16일 새벽 3시는 경계 전이라 15일의 공부일이다.
        #expect(read(at(16, 3)) == "내일")
        #expect(read(at(24, 12)) == "1주 뒤")
    }

    @Test func relativeTimeStopsExactlyAtADay() async {
        await propertyCheck(input: Gen.int(in: -200_000...200_000)) { seconds in
            let now = Date(timeIntervalSince1970: 1_794_800_000)
            let text = RelativeTime.text(until: now + TimeInterval(seconds), from: now)
            #expect((text == nil) == (abs(seconds) >= 24 * 3600))
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
