import Foundation

public enum NotificationPlan {
    public static func build(
        courses: [CourseFile], reviewCount: (Date) -> Int, settings: NotificationSettings,
        now: Date, calendar: Calendar, reviewDays: Int = 7
    ) -> [PlannedNotification] {
        func at(_ minute: Int, dayOffset: Int, from date: Date) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date))!
            return calendar.date(byAdding: .minute, value: minute, to: day)!
        }

        let deadline = settings[.assignmentDue]
        let eve = settings[.examDayBefore]
        let morning = settings[.examMorning]
        let review = settings[.dailyReview]
        var out: [PlannedNotification] = []
        for file in courses {
            let course = file.course.id
            if deadline.on {
                for a in file.assignments where a.status == .todo || a.status == .doing {
                    guard let due = a.due else { continue }
                    for hours in deadline.leadHours ?? [] {
                        out.append(
                            .init(
                                id: "due-\(a.id)-\(hours)", date: due - Double(hours) * 3600, kind: .assignmentDue(hoursBefore: hours),
                                courseId: course, subject: a.title, at: due))
                    }
                }
            }

            for exam in file.exams {
                guard let start = exam.start else { continue }
                if eve.on, let minute = eve.minute {
                    out.append(
                        .init(
                            id: "exam-eve-\(exam.id)", date: at(minute, dayOffset: -1, from: start),
                            kind: .examDayBefore, courseId: course, subject: exam.title, at: start))
                }
                if morning.on, let minute = morning.minute, at(minute, dayOffset: 0, from: start) < start {
                    out.append(
                        .init(
                            id: "exam-morning-\(exam.id)", date: at(minute, dayOffset: 0, from: start), kind: .examMorning,
                            courseId: course, subject: exam.title,
                            at: start))
                }
            }

            let absences = GradeCalculator.absences(in: file.heldAttendance(at: now), policy: file.policy)
            if settings[.attendance].on, GradeCalculator.absencesUntilNextCap(absences: absences, policy: file.policy) == 1 {
                out.append(
                    .init(
                        id: "attendance-\(course)-\(absences)", date: now, kind: .attendanceOneAway(absences: absences),
                        courseId: course, subject: file.course.title, at: nil))
            }
        }

        if review.on, let minute = review.minute {
            for day in 0...reviewDays {
                let date = at(minute, dayOffset: day, from: now)
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
