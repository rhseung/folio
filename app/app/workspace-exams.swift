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

    func examSummaryNotes(course id: UUID) -> [UUID: UUID] {
        let notes = (try? course(id)?.store.notes()) ?? []
        return Dictionary(notes.compactMap { n in
            guard n.meta.kind == .examSummary, let exam = n.meta.examId, let note = n.meta.id else { return nil }
            return (exam, note)
        }, uniquingKeysWith: { a, _ in a })
    }

    /// The exam's summary note, created from the template the first time.
    func openExamSummary(_ exam: Exam, course id: UUID) -> UUID? {
        run(ExamSummary(course: id, exam: exam.id))?.made
    }
}
