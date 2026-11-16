import FolioActions
import FolioDomain
import Foundation
import Observation

// 오늘 화면은 이번 학기의 모든 과목을, 과목 화면은 그 과목만 묶는다.
@MainActor @Observable
final class OverdueAssignmentsModel {
    let workspace: Workspace
    let courseId: UUID?
    var editing: Editing?

    init(workspace: Workspace, course: UUID? = nil) {
        self.workspace = workspace
        courseId = course
    }

    struct Editing: Identifiable {
        var course: LoadedCourse
        var assignment: Assignment
        var id: UUID { assignment.id }
    }

    struct Row: Identifiable {
        var courseId: UUID
        var assignment: Assignment
        var due: String
        var ceiling: String?
        // 지금 내도 0점이다.
        var lost: Bool
        // 마감이 지났는데 LMS에는 아직 내지 않았다. Folio에서 제출함으로 둔 과제도 이것 때문에 여기 온다.
        var lms: URL?
        var submitted: Bool { assignment.status == .submitted }
        var id: UUID { assignment.id }
    }

    var showsCourse: Bool { courseId == nil }

    private var courses: [LoadedCourse] {
        courseId.map { id in workspace.course(id).map { [$0] } ?? [] } ?? workspace.currentCourses
    }

    func rows(now: Date) -> [Row] {
        courses.flatMap { c in
            let unsubmitted = workspace.lms.snapshot.map { LMSInbox.unsubmitted($0, in: c.file, now: now) } ?? [:]
            let overdue = Set(c.file.overdueAssignments(at: now).map(\.id))
            return c.file.assignments.filter { overdue.contains($0.id) || unsubmitted[$0.id] != nil }
                .map { row($0, in: c, lms: unsubmitted[$0.id]?.url, now: now) }
        }
        .sorted { ($0.assignment.due ?? .distantPast, $0.assignment.title) < ($1.assignment.due ?? .distantPast, $1.assignment.title) }
    }

    private func row(_ a: Assignment, in course: LoadedCourse, lms: URL?, now: Date) -> Row {
        let calendar = workspace.calendar
        let due = a.due ?? now
        // 지난 날 수는 감점과 같은 셈(`LateRule.lateDays`)으로 센다. 그래야 "2일 지남"과 "최대 80%"가 어긋나지 않는다.
        let past = String(localized: .assignmentsOverdueDays(LateRule.lateDays(due: due, at: now)))
        let when = CourseFile.deadline(due, calendar: calendar)
        let late = course.file.lateness(of: a, at: now)
        let ceiling = late?.ceiling.map { ceiling in
            guard ceiling > 0 else { return String(localized: .overdueCeilingZero) }
            let percent = Int((ceiling * 100).rounded())
            return late?.nextDrop.map { String(localized: .overdueCeilingUntil(percent, CourseFile.deadline($0, calendar: calendar))) }
                ?? String(localized: .overdueCeiling(percent))
        }
        return Row(
            courseId: course.id, assignment: a, due: String(localized: .overdueDue(when, past)), ceiling: ceiling,
            lost: late?.ceiling == 0, lms: lms)
    }

    func courseTitle(_ row: Row) -> String { workspace.course(row.courseId)?.title ?? "" }

    func edit(_ row: Row) {
        guard let course = workspace.course(row.courseId) else { return }
        editing = Editing(course: course, assignment: row.assignment)
    }

    func submit(_ row: Row) { set(row, .submitted) }

    func miss(_ row: Row) { set(row, .missed) }

    private func set(_ row: Row, _ status: AssignmentStatus) {
        workspace.run(AssignmentStatusSet(course: row.courseId, assignment: row.id, status: status))
    }
}
