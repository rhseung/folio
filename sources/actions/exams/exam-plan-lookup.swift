import FolioCore
import FolioDomain
import Foundation

extension Exam {
    // 항목 하나라도 없으면 아무것도 바꾸기 전에 멈춘다.
    func planItems(_ ids: [UUID]) throws -> [ExamPlanItem] {
        try ids.map { id in
            guard let item = plan.first(where: { $0.id == id && !$0.isRemoved }) else {
                throw ActionError.notFound(String(localized: .errorNotFoundPlanItem))
            }
            return item
        }
    }
}

extension ActionContext {
    func studyDay() throws -> LocalDate { try settings().studyDay(of: now, calendar: calendar) }

    // 날짜가 없는 시험은 계획이 없으므로 항목을 옮길 수 없다.
    func examDay(of exam: Exam) throws -> LocalDate {
        guard let start = exam.start else { throw ActionError.rule(String(localized: .errorPlanNeedsExamTime)) }
        return try settings().studyDay(of: start, calendar: calendar)
    }
}
