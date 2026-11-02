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

    /// A credited term's record never shows on a timetable, so it gets no class times to set.
    var holdsClasses: Bool { workspace.semester(of: course)?.term.holdsClasses ?? true }

    // `course set` has no title field: a record's name goes through `transcript set`.
    private var rename: TranscriptSet? {
        let title = title.trimmingCharacters(in: .whitespaces)
        return title == course.title ? nil : TranscriptSet(course: course.id, title: .set(title))
    }

    /// Nil while the credits field is empty: there is no number to save yet.
    private var update: CourseSet? {
        credits.map { CourseSet(course: course.id, [.credits($0), .gradingMode(mode), .icon(icon), .schedule(schedule)]) }
    }

    /// Why the domain's rules refuse the draft, tried before saving rather than spelled out again here.
    var note: String? { rename.flatMap { workspace.refusal($0) } ?? update.flatMap { workspace.refusal($0) } }

    var canSave: Bool { update != nil && note == nil }

    func confirm() -> Bool {
        guard canSave, let update else { return false }
        if let rename { guard workspace.run(rename) != nil else { return false } }
        return workspace.run(update) != nil
    }
}
