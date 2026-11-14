import Foundation
import Testing

@testable import FolioDomain

// 알림 종류를 표로 옮기기 전의 `NotificationPlan.build`가 낸 계획을 그대로 적었다. 표로 읽어도 같은 계획이어야 한다.
struct NotificationTableTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static func id(_ last: String) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-0000000000\(last)") ?? UUID() }

    static func file() -> CourseFile {
        let device = id("01")
        let now = at(23, 12)
        var file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        file.course.id = id("C1")
        var a1 = Assignment(device: device, at: now, title: "HW5", due: at(25, 23, 59))
        a1.id = id("A1")
        var a2 = Assignment(device: device, at: now, title: "HW4", due: at(23, 18))
        a2.id = id("A2")
        file.assignments = [a1, a2]
        var e1 = Exam(device: device, at: now, title: "중간고사")
        e1.id = id("E1")
        e1.start = at(26, 9)
        var e2 = Exam(device: device, at: now, title: "퀴즈")
        e2.id = id("E2")
        e2.start = at(27, 7, 30)
        file.exams = [e1, e2]
        file.policy.attendanceCap = [AttendanceCap(absences: 6, maxGrade: UUID())]
        let sessions = (0..<5).map { Session(device: device, at: now, week: 1, date: at(1 + $0, 9)) }
        file.sessions = sessions
        file.attendance = sessions.map { Attendance(device: device, at: now, sessionId: $0.id, state: .absent) }
        return file
    }

    static func plan(_ settings: NotificationSettings) -> String {
        let file = file()
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        let plan = NotificationPlan.build(
            courses: [file], reviewCount: { $0 < at(26, 0) ? 2 : 0 }, settings: settings, now: at(23, 12), calendar: calendar)
        return plan.map { "\($0.id.replacingOccurrences(of: "-\(file.course.id)", with: "")) \(f.string(from: $0.date)) \($0.kind)" }
            .joined(separator: "\n")
    }

    @Test func plansStayTheSame() {
        var custom = NotificationSettings()
        custom[.assignmentDue].leadHours = [48, 6, 1]
        custom[.examDayBefore].minute = 20 * 60 + 30
        custom[.examMorning].minute = 8 * 60
        custom[.dailyReview].minute = 22 * 60
        var off = NotificationSettings()
        off[.examDayBefore].on = false
        off[.attendance].on = false
        off[.examMorning].minute = 7 * 60

        #expect(
            [NotificationSettings(), custom, off].map(Self.plan).joined(separator: "\n---\n")
                == """
                attendance-5 2026-10-23T12:00:00+09:00 attendanceOneAway(absences: 5)
                due-00000000-0000-0000-0000-0000000000A2-3 2026-10-23T15:00:00+09:00 assignmentDue(hoursBefore: 3)
                review-2026-10-24 2026-10-24T09:00:00+09:00 dailyReview(count: 2)
                due-00000000-0000-0000-0000-0000000000A1-24 2026-10-24T23:59:00+09:00 assignmentDue(hoursBefore: 24)
                review-2026-10-25 2026-10-25T09:00:00+09:00 dailyReview(count: 2)
                due-00000000-0000-0000-0000-0000000000A1-3 2026-10-25T20:59:00+09:00 assignmentDue(hoursBefore: 3)
                exam-eve-00000000-0000-0000-0000-0000000000E1 2026-10-25T21:00:00+09:00 examDayBefore
                exam-morning-00000000-0000-0000-0000-0000000000E1 2026-10-26T08:00:00+09:00 examMorning
                exam-eve-00000000-0000-0000-0000-0000000000E2 2026-10-26T21:00:00+09:00 examDayBefore
                ---
                due-00000000-0000-0000-0000-0000000000A2-6 2026-10-23T12:00:00+09:00 assignmentDue(hoursBefore: 6)
                attendance-5 2026-10-23T12:00:00+09:00 attendanceOneAway(absences: 5)
                due-00000000-0000-0000-0000-0000000000A2-1 2026-10-23T17:00:00+09:00 assignmentDue(hoursBefore: 1)
                review-2026-10-23 2026-10-23T22:00:00+09:00 dailyReview(count: 2)
                due-00000000-0000-0000-0000-0000000000A1-48 2026-10-23T23:59:00+09:00 assignmentDue(hoursBefore: 48)
                review-2026-10-24 2026-10-24T22:00:00+09:00 dailyReview(count: 2)
                due-00000000-0000-0000-0000-0000000000A1-6 2026-10-25T17:59:00+09:00 assignmentDue(hoursBefore: 6)
                exam-eve-00000000-0000-0000-0000-0000000000E1 2026-10-25T20:30:00+09:00 examDayBefore
                review-2026-10-25 2026-10-25T22:00:00+09:00 dailyReview(count: 2)
                due-00000000-0000-0000-0000-0000000000A1-1 2026-10-25T22:59:00+09:00 assignmentDue(hoursBefore: 1)
                exam-morning-00000000-0000-0000-0000-0000000000E1 2026-10-26T08:00:00+09:00 examMorning
                exam-eve-00000000-0000-0000-0000-0000000000E2 2026-10-26T20:30:00+09:00 examDayBefore
                ---
                due-00000000-0000-0000-0000-0000000000A2-3 2026-10-23T15:00:00+09:00 assignmentDue(hoursBefore: 3)
                review-2026-10-24 2026-10-24T09:00:00+09:00 dailyReview(count: 2)
                due-00000000-0000-0000-0000-0000000000A1-24 2026-10-24T23:59:00+09:00 assignmentDue(hoursBefore: 24)
                review-2026-10-25 2026-10-25T09:00:00+09:00 dailyReview(count: 2)
                due-00000000-0000-0000-0000-0000000000A1-3 2026-10-25T20:59:00+09:00 assignmentDue(hoursBefore: 3)
                exam-morning-00000000-0000-0000-0000-0000000000E1 2026-10-26T07:00:00+09:00 examMorning
                exam-morning-00000000-0000-0000-0000-0000000000E2 2026-10-27T07:00:00+09:00 examMorning
                """)
    }

    // 종류마다 켜기가 있고, 시각과 마감 전 시간은 그 종류가 쓰는 칸에만 있다. 모두 설정 항목으로 선언되어 있다.
    @Test func everyKindReadsItsFieldsFromSettingItems() {
        let defaults = NotificationSettings()
        for kind in NotificationSettings.Kind.allCases {
            #expect(kind.item(.on) != nil, "\(kind)")
            #expect(defaults[kind] == kind.defaultRule)
        }
        #expect(defaults[.examMorning] == .init(on: true, minute: 8 * 60))
        #expect(defaults[.assignmentDue] == .init(on: true, leadHours: [24, 3]))
        #expect(defaults[.attendance] == .init(on: true))
    }

    @Test func settingsSetValidatesTheNewKeys() throws {
        let root = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(Settings()))
        #expect(SettingItem.unknown("notifications.examMorning.minute") == nil)
        #expect(SettingItem.unknown("notifications.examMorningMinute") != nil)
        var bad = root
        bad["notifications"]?["examMorning"]?["minute"] = .number(24 * 60)
        #expect(!SettingItem.problems(in: bad, under: "notifications.examMorning.minute").isEmpty)
        #expect(SettingItem.problems(in: root).isEmpty)
    }
}
