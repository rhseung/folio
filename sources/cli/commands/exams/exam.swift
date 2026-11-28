import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension Resolver {
    func planItem(_ name: String, in exam: Exam, course c: CourseRef) throws -> ExamPlanItem {
        // 앱이 놓은 항목은 제목을 저장하지 않으므로 대상에서 만든 이름("기말 03 증가 경로 정독")으로 찾는다.
        try pick(
            name, exam.plan.filter { !$0.isRemoved }, what: ItemKind.examPlanItem.noun, names: { [c.file.title(of: $0)] },
            ref: { "\(c.code)/\(exam.title) \(c.file.title(of: $0))" })
    }
}
