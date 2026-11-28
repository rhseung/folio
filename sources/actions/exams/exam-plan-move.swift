import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan move", "공부 계획 항목을 고른 날로 옮기기. 옮긴 항목은 다시 놓아도 그 날에 남는다",
    discussion: "옮길 수 있는 날은 오늘부터 시험 전날까지다.", done: "{items}을(를) {day}로 옮겼습니다",
    examples: [#"folio exam plan move EC4207/기말고사 "교재 3장 다시 읽기" --day 2026-12-05"#],
    phrases: ["계획 옮기", "다른 날로", "날짜 고르기"], panel: true)
public struct ExamPlanMove {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 항목 이름이나 UUID. 정리 노트의 단계는 "<노트> <단계>"다
    @Arg var items: [ExamPlanItem.ID]
    /// 새 날짜. 2026-12-03
    var day: LocalDate

    public func run(_ ctx: ActionContext) throws {
        let file = try ctx.file(course)
        let examDay = try ctx.examDay(of: file.exams[try index(exam, in: file.exams, .valueExam)])
        guard Exam.planDays(today: try ctx.studyDay(), examDay: examDay).contains(day) else {
            throw ActionError.rule(String(localized: .errorPlanMoveDay))
        }
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                _ = try e.planItems(items)
                let before = e.plan
                e.movePlan(items, to: day)
                if e.plan != before { e.touch(by: ctx.device, at: ctx.now) }
            }
        }
    }
}
