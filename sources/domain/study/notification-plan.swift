import FolioCore
import Foundation

public enum NotificationPlan {
    public static func build(
        courses: [CourseFile], settings: NotificationSettings,
        now: Date, calendar: Calendar, days: Int = 7
    ) -> [PlannedNotification] {
        func at(_ minute: Int, dayOffset: Int, from date: Date) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date))!
            return calendar.date(byAdding: .minute, value: minute, to: day)!
        }

        let deadline = settings[.assignmentDue]
        let eve = settings[.examDayBefore]
        let morning = settings[.examMorning]
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

        // 하루에 한 번 그 시각에 마감이 지나 있을 과제를 모은다. 그 사이에 내면 다시 예약할 때 빠진다.
        let overdue = settings[.assignmentOverdue]
        if overdue.on, let minute = overdue.minute {
            for day in 0...days {
                let date = at(minute, dayOffset: day, from: now)
                guard date > now else { continue }
                let late = courses.flatMap { f in f.overdueAssignments(at: date).map { (course: f.course.id, assignment: $0) } }
                guard let first = late.first else { continue }
                let one = late.count == 1
                out.append(
                    .init(
                        id: "overdue-\(LocalDate(date, in: calendar))", date: date, kind: .assignmentOverdue(count: late.count),
                        courseId: one ? first.course : nil, subject: one ? first.assignment.title : "", at: one ? first.assignment.due : nil
                    ))
            }
        }

        return out.filter { $0.date >= now }.sorted { $0.date < $1.date }
    }
}
