import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan advance", "뒤 날의 공부 계획 항목을 오늘로 앞당기기. 그 항목만 옮긴다", done: "{items}을(를) 오늘로 앞당겼습니다",
    examples: [#"folio exam plan advance EC4207/기말고사 "교재 3장 다시 읽기""#], phrases: ["오늘로 앞당기", "미리 하기", "계획 앞당기기"], panel: true)
public struct ExamPlanAdvance {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 항목 이름이나 UUID. 정리 노트의 단계는 "<노트> <단계>"다
    @Arg var items: [ExamPlanItem.ID]

    public func run(_ ctx: ActionContext) throws {
        let today = try ctx.studyDay()
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard try e.planItems(items).allSatisfy({ $0.day > today }) else {
                    throw ActionError.rule(String(localized: .errorPlanAdvanceNotLater))
                }
                e.advancePlan(items, today: today)
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
