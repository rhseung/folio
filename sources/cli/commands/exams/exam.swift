import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension Resolver {
    func planItem(_ name: String, in exam: Exam, course c: CourseRef) throws -> ExamPlanItem {
        try pick(name, exam.plan, what: ItemKind.examPlanItem.noun, names: { [$0.title] }, ref: { "\(c.code)/\(exam.title) \($0.title)" })
    }
}
