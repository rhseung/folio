import FolioActions
import FolioDomain
import Foundation
import Observation

/// The draft behind the sheet for a course kept only in transcript.json (a colloquium, a credited course).
@MainActor @Observable
final class EditRecordModel {
    let workspace: Workspace
    let course: Course
    var title: String
    var credits: Double?
    var mode: GradingMode
    var icon: String?
    var schedule: [ClassTime]

    init(workspace: Workspace, course: Course) {
        self.workspace = workspace
        self.course = course
        title = course.title
        credits = course.credits
        mode = course.gradingMode
        icon = course.icon
        schedule = course.schedule
    }

    var badTime: Bool { schedule.contains { $0.endMinute <= $0.startMinute } }

    var canSave: Bool { (credits ?? -1) >= 0 && !title.trimmingCharacters(in: .whitespaces).isEmpty && !badTime }

    var note: String? { badTime ? String(localized: .classTimesBadTime) : nil }

    func confirm() -> Bool {
        guard canSave, let credits else { return false }
        let title = title.trimmingCharacters(in: .whitespaces)
        // `course set` has no title field: a record's name goes through `transcript set`.
        if title != course.title {
            guard workspace.run(TranscriptSet(course: course.id, title: .set(title))) != nil else { return false }
        }
        return workspace.run(CourseSet(course: course.id, [.credits(credits), .gradingMode(mode), .icon(icon), .schedule(schedule)])) != nil
    }
}
