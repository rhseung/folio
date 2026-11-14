import FolioDomain
import Foundation
import Testing

struct StudyActivityTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func idleGapSplitsSpanFiveMinutesAfterLastInput() {
        var span = ActivitySpan(start: t0)
        #expect(span.input(at: t0 + 60) == nil)
        #expect(span.input(at: t0 + 60 + 300) == nil)  // 정확히 한도에 닿아도 활동 중으로 센다.
        let done = span.input(at: t0 + 60 + 300 + 301)
        #expect(done == DateInterval(start: t0, end: t0 + 360 + 300))
        #expect(span.start == t0 + 661)
    }

    @Test func endStopsAtTheIdleLimit() {
        var span = ActivitySpan(start: t0)
        _ = span.input(at: t0 + 100)
        #expect(span.end(at: t0 + 200).end == t0 + 200)
        #expect(span.end(at: t0 + 3600).end == t0 + 400)
    }

    @Test func overlapAcrossDevicesCountsOnceIncludingContainedAndTouching() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 10))!
        let course = UUID()
        func s(_ from: Double, _ to: Double) -> StudySessionEvent {
            StudySessionEvent(courseId: course, start: base + from * 60, end: base + to * 60, screen: "course")
        }

        // Mac 0부터 60, iPad 10부터 20(안쪽), 손으로 쓴 60부터 90(맞닿음), 빈 100부터 100이다.
        let perDay = StudyTime.perDay([s(0, 60), s(10, 20), s(60, 90), s(100, 100)], settings: Settings(), calendar: calendar)
        #expect(perDay == [LocalDate("2026-10-23")!: 90 * 60])
    }
}

struct BackupRetentionTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    @Test func keepsDailyForThirtyDaysThenNewestPerWeek() {
        let today = LocalDate("2026-10-23")!
        let days = (0..<60).map { today.adding(days: -$0) }
        let kept = BackupRetention.keep(days, today: today, dailyDays: 30, calendar: calendar)

        #expect(days.prefix(30).allSatisfy(kept.contains))

        // 2026-09-23은 30일째(수요일)이다. 그 ISO 주는 09-21 월요일부터 09-27 일요일까지이고, 가장 최근의 이전 기록은 09-23이다.
        #expect(kept.contains(LocalDate("2026-09-23")!))
        #expect(!kept.contains(LocalDate("2026-09-22")!))

        // 이전의 꽉 찬 주(09-14부터 09-20까지)는 일요일만 남긴다.
        #expect(kept.contains(LocalDate("2026-09-20")!))
        #expect((14...19).allSatisfy { !kept.contains(LocalDate(year: 2026, month: 9, day: $0)!) })
        #expect(kept.count == 30 + 5)  // 이전 주의 기록은 09-23, 09-20, 09-13, 09-06, 08-30이다.
    }
}

struct ServiceSettingsTests {
    @Test func oldSettingsFileGetsNewDefaults() throws {
        let s = try JSONDecoder().decode(
            Settings.self, from: Data(#"{"dayBoundaryMinutes":300,"notifications":{"examMorning":false}}"#.utf8))
        #expect(s.dayBoundaryMinutes == 300)
        #expect(s.notifications.examMorning == false)
        #expect(s.notifications.assignmentLeadHours == [24, 3] && s.notifications.dailyReview)
        #expect(s.backup == BackupSettings())
        #expect(s.noteSections(for: .review) == NoteTemplate.defaultSections(for: .review))
    }

    @Test func templateOverrideIsUsed() {
        let s = Settings(noteTemplates: [NoteKind.unit.rawValue: ["요약"]])
        #expect(NoteTemplate.body(for: .unit, title: "T", sections: s.noteSections(for: .unit)) == "# T\n\n## 요약\n\n")
    }
}

struct NotificationPlanTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    let device = UUID()

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func plansDeadlinesExamsReviewsAndAttendance() {
        let now = at(23, 12)
        var file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        file.assignments = [
            Assignment(device: device, at: now, title: "HW5", due: at(24, 23)),
            Assignment(device: device, at: now, title: "HW4", due: at(23, 14)),
        ]
        var exam = Exam(device: device, at: now, title: "중간고사")
        exam.start = at(26, 9)
        file.exams = [exam]
        file.policy.attendanceCap = [AttendanceCap(absences: 6, maxGrade: UUID())]
        let sessions = (0..<5).map { Session(device: device, at: now, week: 1, date: at(1 + $0, 9)) }
        file.sessions = sessions
        file.attendance = sessions.map { Attendance(device: device, at: now, sessionId: $0.id, state: .absent) }

        let plan = NotificationPlan.build(
            courses: [file], reviewCount: { $0 < at(25, 0) ? 2 : 0 }, settings: NotificationSettings(),
            now: now, calendar: calendar)
        let ids = plan.map(\.id)
        #expect(plan.first?.kind == .attendanceOneAway(absences: 5))
        #expect(plan.filter { if case .assignmentDue = $0.kind { true } else { false } }.map(\.date) == [at(23, 23), at(24, 20)])
        #expect(ids.contains("exam-eve-\(exam.id)") && ids.contains("exam-morning-\(exam.id)"))
        #expect(plan.first { $0.id == "exam-eve-\(exam.id)" }?.date == at(25, 21))
        #expect(plan.filter { if case .dailyReview = $0.kind { true } else { false } }.map(\.date) == [at(24, 9)])
        #expect(plan.map(\.date) == plan.map(\.date).sorted())
    }

    @Test func turnedOffKindsAreLeftOut() {
        var off = NotificationSettings()
        off.assignmentDue = false
        off.dailyReview = false
        let now = at(23, 12)
        var file = CourseFile(course: Course(device: device, at: now, title: "x"))
        file.assignments = [Assignment(device: device, at: now, title: "HW5", due: at(24, 23))]
        #expect(NotificationPlan.build(courses: [file], reviewCount: { _ in 3 }, settings: off, now: now, calendar: calendar).isEmpty)
    }
}

struct NoteTemplateTests {
    @Test func aTexNoteHasTheSameSectionsAndEscapesItsTitle() {
        let tex = NoteTemplate.body(for: .unit, title: "A_1 & 50%", sections: ["요약"], format: .tex)
        #expect(tex.contains("\\section*{A\\_1 \\& 50\\%}"))
        #expect(tex.contains("\\subsection*{요약}"))
        #expect(tex.hasSuffix("\\end{document}\n"))
    }

    @Test func formatComesFromTheExtension() {
        #expect(NoteFormat(path: "Notes/a.TEX") == .tex)
        #expect(NoteFormat(path: "Notes/a.md") == .markdown)
        #expect(NoteFormat(path: "Notes/a.pdf") == nil)
    }
}
