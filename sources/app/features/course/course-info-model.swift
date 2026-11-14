import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class CourseInfoModel {
    let workspace: Workspace
    var memo = ""

    init(workspace: Workspace) { self.workspace = workspace }

    func people(_ course: Course) -> [Person] {
        course.instructorIds.compactMap { id in workspace.catalog.people.first { $0.id == id } }
    }

    func detail(_ p: Person) -> String? {
        [p.office, p.officeHours].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty
    }

    func mailURL(_ p: Person) -> URL? { workspace.mailURL(to: p.email) }

    func saveMemo(_ courseId: UUID) {
        workspace.run(CourseSet(course: courseId, [.memo(memo)]))
    }
}
