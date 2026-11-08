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
            : QuickAdd.parse(text, courses: courses, codes: workspace.catalog.codes, fixedCourse: fixedCourse, now: workspace.now, calendar: workspace.calendar)
    }

    func canAdd(_ parsed: QuickAdd) -> Bool { parsed.courseId != nil && !parsed.title.isEmpty }

    func courseTitle(_ parsed: QuickAdd) -> String? { parsed.courseId.flatMap { workspace.course($0)?.title } }

    func due(_ parsed: QuickAdd) -> String? {
        parsed.due?.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).hour().minute())
    }

    enum Summary: Hashable {
        case due(String)
        case weekly
        case title(String)
    }

    /// What the line will save, after the course: the deadline, 매주, and the title as it goes in.
    func summary(_ parsed: QuickAdd) -> [Summary] {
        var items: [Summary] = []
        if let due = due(parsed) { items.append(.due(due)) }
        if parsed.repeats == .weekly { items.append(.weekly) }
        if !parsed.title.isEmpty { items.append(.title(parsed.title)) }
        return items
    }

    /// Whether it went in; the line clears only then.
    @discardableResult
    func add(_ parsed: QuickAdd) -> Bool {
        guard let id = parsed.courseId, !parsed.title.isEmpty,
              workspace.run(AssignmentAdd(course: id, title: parsed.title, due: parsed.due, repeats: parsed.repeats)) != nil else { return false }
        text = ""
        return true
    }
}
