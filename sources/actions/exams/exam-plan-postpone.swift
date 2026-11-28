import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan postpone", "공부 계획 항목을 다음 공부일로 미루기. 그 항목만 옮기고 뒤 항목은 제자리에 둔다",
    discussion: "오늘이나 지난 날의 항목은 내일로, 뒤 날의 항목은 그 다음 날로 간다. 미룬 항목은 옮겨 간 날에 밀림으로 보인다. 시험 전날 뒤로는 미룰 수 없다.",
    done: "{items}을(를) 다음 날로 미뤘습니다", examples: [#"folio exam plan postpone EC4207/기말고사 "교재 3장 다시 읽기""#],
    phrases: ["내일로 미루", "계획 미루기", "오늘 못 해"], panel: true)
public struct ExamPlanPostpone {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 항목 이름이나 UUID. 정리 노트의 단계는 "<노트> <단계>"다
    @Arg var items: [ExamPlanItem.ID]

    public func run(_ ctx: ActionContext) throws {
        let today = try ctx.studyDay()
        let file = try ctx.file(course)
        let examDay = try ctx.examDay(of: file.exams[try index(exam, in: file.exams, .valueExam)])
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard try e.planItems(items).allSatisfy({ Exam.postponedDay(of: $0, today: today) < examDay }) else {
                    throw ActionError.rule(String(localized: .errorPlanPostponePastExam))
                }
                e.postponePlan(items, today: today)
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
