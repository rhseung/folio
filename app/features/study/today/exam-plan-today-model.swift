import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ExamPlanTodayModel {
    let workspace: Workspace

    init(workspace: Workspace) { self.workspace = workspace }

    var courseIds: [UUID] { workspace.currentCourses.map(\.id) }

    var items: [ExamPlan.DayItem] { ExamPlan.items(on: workspace.today, courses: workspace.currentCourses.map(\.file)) }

    func note(_ items: [ExamPlan.DayItem]) -> String {
        String(localized: .examsPlanDone(items.filter { isDone($0) }.count, items.count))
    }

    func isDone(_ entry: ExamPlan.DayItem) -> Bool { workspace.study(of: entry.courseId)?.isDone(entry.item, in: entry.exam) ?? false }

    func detail(_ entry: ExamPlan.DayItem) -> String {
        "\(workspace.course(entry.courseId)?.title ?? "") · \(entry.exam.title)"
    }

    func toggle(_ entry: ExamPlan.DayItem) {
        workspace.setPlanItem(entry.item.id, done: !isDone(entry), course: entry.courseId)
    }
}
