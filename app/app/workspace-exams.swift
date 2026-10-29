import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    /// Plan items whose latest `plan_check` across every device's log says done.
    func donePlanItems(in courseIds: [UUID]) -> Set<UUID> {
        let events = courseIds.compactMap(course).flatMap { (try? $0.store.log.readAll()) ?? [] }
            .events(PlanCheckEvent.self)
        return ExamPlan.done(events)
    }

    func setPlanItem(_ item: UUID, done: Bool, course id: UUID) {
        run(ExamPlanCheck(course: id, item: item, done: done))
    }
}
