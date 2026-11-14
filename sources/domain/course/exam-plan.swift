import Foundation

public enum ExamPlan {
    public struct DayItem: Sendable, Equatable {
        public var courseId: UUID
        public var exam: Exam
        public var item: ExamPlanItem
    }

    // 이벤트는 여러 기기의 로그에서 순서 없이 들어온다.
    public static func done(_ events: [(at: Date, event: PlanCheckEvent)]) -> Set<UUID> {
        var latest: [UUID: (at: Date, done: Bool)] = [:]
        for (at, e) in events where latest[e.itemId].map({ at >= $0.at }) ?? true {
            latest[e.itemId] = (at, e.done)
        }
        return Set(latest.filter(\.value.done).keys)
    }

    public static func items(on day: LocalDate, courses: [CourseFile]) -> [DayItem] {
        courses.flatMap { file in
            file.exams.flatMap { exam in
                exam.plan.filter { $0.day == day }.map { DayItem(courseId: file.course.id, exam: exam, item: $0) }
            }
        }
        .sorted { ($0.exam.start ?? .distantFuture, $0.item.title) < ($1.exam.start ?? .distantFuture, $1.item.title) }
    }
}
