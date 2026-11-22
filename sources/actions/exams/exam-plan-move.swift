import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan move", "공부 계획 항목을 다른 날로 옮기기. 옮긴 항목은 다시 짜도 그 날에 남는다", done: "'{item}'을(를) {day}로 옮겼습니다",
    examples: [#"folio exam plan move EC4207/중간고사 "트리 단원 복습" --day 2026-10-19"#], phrases: ["계획 옮기", "내일로 미루", "다른 날로"], panel: true)
public struct ExamPlanMove {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 항목 제목이나 UUID
    @Arg var item: ExamPlanItem.ID
    /// 새 날짜. 2026-10-19
    var day: LocalDate

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                let i = try index(item, in: e.plan, .valuePlanItem)
                guard e.plan[i].day != day || !e.plan[i].isEdited else { return }
                e.plan[i].day = day
                e.plan[i].edited = true
                e.plan[i].carried = nil
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
