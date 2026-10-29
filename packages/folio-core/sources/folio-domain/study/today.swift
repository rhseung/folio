import Foundation

/// `study_session` log event: time a course screen was in front (docs/SPEC.md "공부 시간").
public struct StudySessionEvent: LogEvent, Equatable {
    public static let type = "study_session"
    public var courseId: UUID
    public var start: Date
    public var end: Date
    /// Which screen: `note`, `ink`, `quiz`, `review`, `pdf`, `manual`, ...
    public var screen: String

    public init(courseId: UUID, start: Date, end: Date, screen: String) {
        self.courseId = courseId
        self.start = start
        self.end = end
        self.screen = screen
    }
}

public enum StudyTime {
    /// Seconds per study day for one course. Overlapping records (two devices open at once) count once;
    /// a record is credited to the study day it started in.
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

    /// `40분`, `2시간`, `1시간 20분`.
    public static func label(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes)분" : minutes % 60 == 0 ? "\(minutes / 60)시간" : "\(minutes / 60)시간 \(minutes % 60)분"
    }
}

extension CourseFile {
    /// Absences so far and the cap the next one reaches, when that next absence would reach it (docs/SPEC.md "알림").
    /// Marks ahead of their class don't count yet.
    public func capOneAway(at now: Date) -> (absences: Int, cap: AttendanceCap)? {
        let absences = GradeCalculator.absences(in: heldAttendance(at: now), policy: policy)
        guard let cap = GradeCalculator.nextCap(absences: absences, policy: policy), cap.absences == absences + 1 else { return nil }
        return (absences, cap)
    }
}

/// Everything the today screen shows (docs/SPEC.md "오늘 화면"), computed from course files and review states.
public struct TodaySummary: Sendable {
    public struct ExamItem: Sendable, Equatable {
        public var courseId: UUID
        public var exam: Exam
        /// Days from today's study day to the exam's calendar day (0 = today).
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
    /// Past sessions with no review note yet, oldest first.
    public var missingReviewNotes: [SessionItem]

    /// - Parameter examHorizonDays: how far ahead exams are listed.
    public static func build(courses: [CourseFile], now: Date, settings: Settings, calendar: Calendar, examHorizonDays: Int = 30) -> TodaySummary {
        let today = settings.studyDay(of: now, calendar: calendar)
        // The study day runs from the boundary to the next boundary, in real time.
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
                // Deadlines use real time: one at 01:00 tonight is still "today" only if it hasn't passed. Every one still
                // ahead shows, however far: a long project is due as surely as tomorrow's homework.
                guard let due = a.due, due >= now else { continue }
                deadlines.append(DeadlineItem(courseId: id, assignment: a, isToday: due < dayEnd))
            }
            for s in file.sessions where !s.isCancelled {
                if s.date >= dayStart && s.date < dayEnd { classes.append(SessionItem(courseId: id, session: s)) }
                // From the moment the class ends, not the next study day: the review note is written the same day.
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
    public struct OngoingClass: Sendable, Equatable {
        public var courseId: UUID
        public var session: Session
        public var end: Date

        public func fraction(at now: Date) -> Double {
            min(1, max(0, now.timeIntervalSince(session.date) / end.timeIntervalSince(session.date)))
        }
    }

    /// The class under way at `now`. Its end comes from the weekly slot it starts in, so a session without one never is.
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
