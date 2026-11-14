import Foundation

public struct StudySessionEvent: LogEvent, Equatable {
    public static let type = "study_session"
    public var courseId: UUID
    public var start: Date
    public var end: Date
    public var screen: String

    public init(courseId: UUID, start: Date, end: Date, screen: String) {
        self.courseId = courseId
        self.start = start
        self.end = end
        self.screen = screen
    }
}

public enum StudyTime {
    public static func perDay(_ sessions: [StudySessionEvent], settings: Settings, calendar: Calendar) -> [LocalDate: TimeInterval] {
        var merged: [(start: Date, end: Date)] = []
        for s in sessions.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, s.start <= last.end {
                merged[merged.count - 1].end = max(last.end, s.end)
            } else {
                merged.append((s.start, s.end))
            }
        }
        var result: [LocalDate: TimeInterval] = [:]
        for m in merged { result[settings.studyDay(of: m.start, calendar: calendar), default: 0] += m.end.timeIntervalSince(m.start) }
        return result
    }

    public static func label(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60
            ? String(localized: .studyTimeMinutes(minutes))
            : minutes % 60 == 0
                ? String(localized: .studyTimeHours(minutes / 60))
                : String(localized: .studyTimeHoursMinutes(minutes / 60, minutes % 60))
    }
}

extension CourseFile {
    public func capOneAway(at now: Date) -> (absences: Int, cap: AttendanceCap)? {
        let absences = GradeCalculator.absences(in: heldAttendance(at: now), policy: policy)
        guard let cap = GradeCalculator.nextCap(absences: absences, policy: policy), cap.absences == absences + 1 else { return nil }
        return (absences, cap)
    }
}

public struct TodaySummary: Sendable {
    public struct ExamItem: Sendable, Equatable {
        public var courseId: UUID
        public var exam: Exam
        public var dDay: Int
    }

    public struct DeadlineItem: Sendable, Equatable {
        public var courseId: UUID
        public var assignment: Assignment
        public var isToday: Bool
    }

    public struct SessionItem: Sendable, Equatable {
        public var courseId: UUID
        public var session: Session
    }

    public var studyDay: LocalDate
    public var exams: [ExamItem]
    public var deadlines: [DeadlineItem]
    public var classesToday: [SessionItem]
    public var missingReviewNotes: [SessionItem]

    public static let examHorizon = 30

    public static func build(courses: [CourseFile], now: Date, settings: Settings, calendar: Calendar, examHorizonDays: Int = examHorizon)
        -> TodaySummary
    {
        let today = settings.studyDay(of: now, calendar: calendar)
        let dayStart = calendar.date(byAdding: .minute, value: settings.dayBoundaryMinutes, to: today.date(in: calendar)!)!
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        var exams: [ExamItem] = []
        var deadlines: [DeadlineItem] = []
        var classes: [SessionItem] = []
        var missing: [SessionItem] = []
        for file in courses {
            let id = file.course.id
            for exam in file.exams {
                guard let start = exam.start, start >= now else { continue }
                let d = today.days(until: LocalDate(start, in: calendar))
                if d <= examHorizonDays { exams.append(ExamItem(courseId: id, exam: exam, dDay: d)) }
            }

            for a in file.assignments where a.status.isOpen {
                // 마감은 실제 시각을 쓴다. 오늘 밤 01:00 마감은 지나지 않았을 때만 오늘 할 일이다.
                guard let due = a.due, due >= now else { continue }
                deadlines.append(DeadlineItem(courseId: id, assignment: a, isToday: due < dayEnd))
            }

            for s in file.sessions where !s.isCancelled {
                if s.date >= dayStart && s.date < dayEnd { classes.append(SessionItem(courseId: id, session: s)) }
                // 복습 노트는 같은 날 쓰므로, 다음 공부일이 아니라 수업이 끝난 순간부터 센다.
                if file.needsReviewNote(s, at: now), (s.end(schedule: file.course.schedule, calendar: calendar) ?? s.date) <= now {
                    missing.append(SessionItem(courseId: id, session: s))
                }
            }
        }

        return TodaySummary(
            studyDay: today,
            exams: exams.sorted { $0.exam.start! < $1.exam.start! },
            deadlines: deadlines.sorted { $0.assignment.due! < $1.assignment.due! },
            classesToday: classes.sorted { $0.session.date < $1.session.date },
            missingReviewNotes: missing.sorted { $0.session.date < $1.session.date }
        )
    }
}

extension TodaySummary {
    public enum CourseHint: Sendable, Equatable {
        case dueToday(Assignment)
        case nextClass(Date)
        case exam(days: Int)
    }

    public func hint(for courseId: UUID, now: Date, examWithinDays: Int = 7) -> CourseHint? {
        if let due = deadlines.first(where: { $0.courseId == courseId && $0.isToday }) { return .dueToday(due.assignment) }
        if let next = classesToday.first(where: { $0.courseId == courseId && $0.session.date > now }) {
            return .nextClass(next.session.date)
        }
        if let exam = exams.first(where: { $0.courseId == courseId && $0.dDay <= examWithinDays }) { return .exam(days: exam.dDay) }
        return nil
    }

    public struct OngoingClass: Sendable, Equatable {
        public var courseId: UUID
        public var session: Session
        public var end: Date

        public func fraction(at now: Date) -> Double {
            min(1, max(0, now.timeIntervalSince(session.date) / end.timeIntervalSince(session.date)))
        }
    }

    public static func ongoingClass(in courses: [CourseFile], at now: Date, calendar: Calendar) -> OngoingClass? {
        for file in courses {
            for s in file.sessions where !s.isCancelled && s.date <= now {
                if let end = s.end(schedule: file.course.schedule, calendar: calendar), now < end {
                    return OngoingClass(courseId: file.course.id, session: s, end: end)
                }
            }
        }
        return nil
    }
}
