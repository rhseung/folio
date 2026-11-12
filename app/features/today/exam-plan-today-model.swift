import FolioDomain
import Foundation
import Observation

/// Today's items from every current course's exam plans.
@MainActor @Observable
final class ExamPlanTodayModel {
    let workspace: Workspace
    private(set) var done: Set<UUID> = []

    init(workspace: Workspace) { self.workspace = workspace }

    var courseIds: [UUID] { workspace.currentCourses.map(\.id) }

    var items: [ExamPlan.DayItem] { ExamPlan.items(on: workspace.today, courses: workspace.currentCourses.map(\.file)) }

    func note(_ items: [ExamPlan.DayItem]) -> String {
        String(localized: .examsPlanDone(items.filter { isDone($0) }.count, items.count))
    }

    func isDone(_ entry: ExamPlan.DayItem) -> Bool { done.contains(entry.item.id) }

    func detail(_ entry: ExamPlan.DayItem) -> String {
        "\(workspace.course(entry.courseId)?.title ?? "") · \(entry.exam.title)"
    }

    func load() { done = workspace.donePlanItems(in: courseIds) }

    /// Checking one appends a `plan_check` event; course.json only holds the items.
    func toggle(_ entry: ExamPlan.DayItem) {
        let new = !isDone(entry)
        workspace.setPlanItem(entry.item.id, done: new, course: entry.courseId)
        if new { done.insert(entry.item.id) } else { done.remove(entry.item.id) }
    }
}
