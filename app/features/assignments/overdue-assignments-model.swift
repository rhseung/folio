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
        var past: String
        // 마감이 지났는데 LMS에는 아직 내지 않았다. Folio에서 제출함으로 둔 과제도 이것 때문에 여기 온다.
        var lms: URL?
        var id: UUID { assignment.id }

        // Folio에서 이미 낸 과제는 지난 때보다 LMS에 아직 안 낸 것이 여기 있는 이유다.
        var trailing: String {
            assignment.status.isOpen || lms == nil ? past : String(localized: .lmsNotSubmitted)
        }
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
        // 과제 목록과 같은 셈으로 지난 때를 쓴다. 마감 시각과 감점은 과제 시트에서 본다.
        let past = RelativeDate.distance(a.due ?? now, from: now, settings: workspace.settings, calendar: workspace.calendar)
        return Row(courseId: course.id, assignment: a, past: past, lms: lms)
    }

    func accent(_ row: Row) -> CourseAccent { workspace.accent(row.courseId) }

    func courseTitle(_ row: Row) -> String { workspace.course(row.courseId)?.title ?? "" }

    func edit(_ row: Row) {
        guard let course = workspace.course(row.courseId) else { return }
        editing = Editing(course: course, assignment: row.assignment)
    }

    func set(_ row: Row, _ status: AssignmentStatus) {
        workspace.run(AssignmentStatusSet(course: row.courseId, assignment: row.id, status: status))
    }
}
