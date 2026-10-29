import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class QuickAddModel {
    let workspace: Workspace
    let fixedCourse: UUID?
    var text = ""

    init(workspace: Workspace, fixedCourse: UUID? = nil) {
        self.workspace = workspace
        self.fixedCourse = fixedCourse
    }

    var parsed: QuickAdd? {
        let courses = workspace.currentCourses.map(\.file.course)
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil
            : QuickAdd.parse(text, courses: courses, codes: workspace.catalog.codes, fixedCourse: fixedCourse, now: .now, calendar: workspace.calendar)
    }

    func canAdd(_ parsed: QuickAdd) -> Bool { parsed.courseId != nil && !parsed.title.isEmpty }

    func courseTitle(_ parsed: QuickAdd) -> String? { parsed.courseId.flatMap { workspace.course($0)?.title } }

    func due(_ parsed: QuickAdd) -> String? {
        parsed.due?.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).hour().minute())
    }

    func add(_ parsed: QuickAdd) {
        guard let id = parsed.courseId, !parsed.title.isEmpty else { return }
        guard workspace.run(AssignmentAdd(course: id, title: parsed.title, due: parsed.due, repeats: parsed.repeats)) != nil else { return }
        text = ""
    }
}
