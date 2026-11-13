import Foundation

public struct PlannedNotification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case assignmentDue(hoursBefore: Int)
        case examDayBefore, examMorning
        case dailyReview(count: Int)
        // 앱이 이미 보낸 알림인지 알 수 있도록 `id`에 결석 횟수를 담는다.
        case attendanceOneAway(absences: Int)
    }

    // 다시 예약할 때 요청을 하나 더 만들지 않고 바꾸도록, 다시 만들어도 같은 값이어야 한다.
    public var id: String
    public var date: Date
    public var kind: Kind
    public var courseId: UUID?
    public var subject: String
    public var at: Date?
}

public enum NotificationPlan {
    public static func build(
        courses: [CourseFile], reviewCount: (Date) -> Int, settings: NotificationSettings,
        now: Date, calendar: Calendar, reviewDays: Int = 7
    ) -> [PlannedNotification] {
        func at(_ minute: Int, dayOffset: Int, from date: Date) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date))!
            return calendar.date(byAdding: .minute, value: minute, to: day)!
        }

        var out: [PlannedNotification] = []
        for file in courses {
            let course = file.course.id
            if settings.assignmentDue {
                for a in file.assignments where a.status == .todo || a.status == .doing {
                    guard let due = a.due else { continue }
                    for hours in settings.assignmentLeadHours {
                        out.append(
                            .init(
                                id: "due-\(a.id)-\(hours)", date: due - Double(hours) * 3600, kind: .assignmentDue(hoursBefore: hours),
                                courseId: course, subject: a.title, at: due))
                    }
                }
            }

            for exam in file.exams {
                guard let start = exam.start else { continue }
                if settings.examDayBefore {
                    out.append(
                        .init(
                            id: "exam-eve-\(exam.id)", date: at(settings.examDayBeforeMinute, dayOffset: -1, from: start),
                            kind: .examDayBefore, courseId: course, subject: exam.title, at: start))
                }
                let morning = at(settings.examMorningMinute, dayOffset: 0, from: start)
                if settings.examMorning, morning < start {
                    out.append(
                        .init(
                            id: "exam-morning-\(exam.id)", date: morning, kind: .examMorning, courseId: course, subject: exam.title,
                            at: start))
                }
            }

            let absences = GradeCalculator.absences(in: file.heldAttendance(at: now), policy: file.policy)
            if settings.attendance, GradeCalculator.absencesUntilNextCap(absences: absences, policy: file.policy) == 1 {
                out.append(
                    .init(
                        id: "attendance-\(course)-\(absences)", date: now, kind: .attendanceOneAway(absences: absences),
                        courseId: course, subject: file.course.title, at: nil))
            }
        }

        if settings.dailyReview {
            for day in 0...reviewDays {
                let date = at(settings.dailyReviewMinute, dayOffset: day, from: now)
                guard date > now else { continue }
                let count = reviewCount(date)
                if count > 0 {
                    out.append(
                        .init(
                            id: "review-\(LocalDate(date, in: calendar))", date: date, kind: .dailyReview(count: count),
                            courseId: nil, subject: "", at: nil))
                }
            }
        }

        return out.filter { $0.date >= now }.sorted { $0.date < $1.date }
    }
}
