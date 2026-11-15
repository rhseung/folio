import Foundation

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
    // 마감이 지났는데 아직 할 일로 남은 과제다. 하루 경계와 상관없이 마감 시각이 지나면 여기로 온다.
    public var overdue: [DeadlineItem]
    public var classesToday: [SessionItem]
    public var missingReviewNotes: [SessionItem]

    public static func build(courses: [CourseFile], now: Date, settings: Settings, calendar: Calendar) -> TodaySummary {
        let today = settings.studyDay(of: now, calendar: calendar)
        let dayStart = settings.start(of: today, calendar: calendar)
        let dayEnd = settings.start(of: today.adding(days: 1), calendar: calendar)

        var exams: [ExamItem] = []
        var deadlines: [DeadlineItem] = []
        var overdue: [DeadlineItem] = []
        var classes: [SessionItem] = []
        var missing: [SessionItem] = []
        for file in courses {
            let id = file.course.id
            for exam in file.exams {
                guard let start = exam.start, start >= now else { continue }
                let d = today.days(until: LocalDate(start, in: calendar))
                if d <= settings.todayExamDays { exams.append(ExamItem(courseId: id, exam: exam, dDay: d)) }
            }

            for a in file.assignments where a.status.isOpen {
                // 마감은 실제 시각을 쓴다. 오늘 밤 01:00 마감은 지나지 않았을 때만 오늘 할 일이다.
                guard let due = a.due, due >= now else { continue }
                deadlines.append(DeadlineItem(courseId: id, assignment: a, isToday: due < dayEnd))
            }
            overdue += file.overdueAssignments(at: now).map { DeadlineItem(courseId: id, assignment: $0, isToday: false) }

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
            overdue: overdue.sorted { ($0.assignment.due ?? .distantPast) < ($1.assignment.due ?? .distantPast) },
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
