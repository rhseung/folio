import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ExamPlanTodayModel {
    let workspace: Workspace
    private let seed = UInt64.random(in: 1...UInt64.max)

    init(workspace: Workspace) { self.workspace = workspace }

    var courseIds: [UUID] { workspace.currentCourses.map(\.id) }

    var items: [ExamPlan.DayItem] { ExamPlan.items(on: workspace.today, courses: workspace.currentCourses.map(\.file)) }

    func note(_ items: [ExamPlan.DayItem]) -> String {
        String(localized: .examsPlanDone(items.filter { isDone($0) }.count, items.count))
    }

    func isDone(_ entry: ExamPlan.DayItem) -> Bool { workspace.study(of: entry.courseId)?.isDone(entry.item, in: entry.exam) ?? false }

    // 앱이 짠 항목은 제목을 저장하지 않으므로 대상에서 이름을 만든다.
    func title(_ entry: ExamPlan.DayItem) -> String {
        workspace.course(entry.courseId)?.file.title(of: entry.item) ?? entry.item.title
    }

    func detail(_ entry: ExamPlan.DayItem) -> String {
        let carried = entry.item.isCarried ? [String(localized: .unitsPlanCarried)] : []
        return ([workspace.course(entry.courseId)?.title ?? "", entry.exam.title] + carried).joined(separator: " · ")
    }

    func solve(_ entry: ExamPlan.DayItem) -> PlanSolve? {
        guard !isDone(entry) else { return nil }
        return workspace.study(of: entry.courseId)?.solve(entry.item, in: entry.exam, seed: seed)
    }

    func toggle(_ entry: ExamPlan.DayItem) {
        workspace.setPlanItem(entry.item.id, done: !isDone(entry), course: entry.courseId)
    }
}
