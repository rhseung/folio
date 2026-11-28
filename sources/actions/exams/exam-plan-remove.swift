import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan rm", "공부 계획에서 항목 빼기. 앱이 놓은 항목은 다시 놓아도 돌아오지 않게 빼 둔다", effect: .removes, confirm: "공부 계획에서 {items}을(를) 뺍니다.",
    done: "공부 계획에서 {items}을(를) 뺐습니다", examples: [#"folio exam plan rm EC4207/기말고사 "교재 3장 다시 읽기" --dry-run"#], panel: true)
public struct ExamPlanRemove {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 항목 이름이나 UUID. 정리 노트의 단계는 "<노트> <단계>"다
    @Arg var items: [ExamPlanItem.ID]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                _ = try e.planItems(items)
                // 사용자가 쓴 할 일은 지운다. 앱이 놓은 항목을 지우면 다음에 다시 놓을 때 같은 대상이 돌아오므로 묘비로 남긴다.
                e.plan.removeAll { items.contains($0.id) && $0.target.kind == .custom }
                for i in e.plan.indices where items.contains(e.plan[i].id) { e.plan[i].removed = true }
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
