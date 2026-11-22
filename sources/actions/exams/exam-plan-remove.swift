import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan rm", "공부 계획 항목 지우기. 앱이 짠 항목은 다시 짜도 돌아오지 않게 빼 둔다", effect: .removes, confirm: "공부 계획 항목 '{item}'을(를) 지웁니다.",
    done: "공부 계획에서 '{item}'을(를) 지웠습니다", examples: [#"folio exam plan rm EC4207/중간고사 "트리 단원 복습" --dry-run"#], panel: true)
public struct ExamPlanRemove {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 항목 제목이나 UUID
    @Arg var item: ExamPlanItem.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard let i = e.plan.firstIndex(where: { $0.id == item }) else {
                    throw ActionError.notFound(String(localized: .errorNotFoundPlanItem))
                }
                // 사용자가 쓴 할 일은 지운다. 앱이 짠 항목을 지우면 다음에 다시 짤 때 같은 대상이 돌아오므로 묘비로 남긴다.
                if e.plan[i].target.kind == .custom {
                    e.plan.remove(at: i)
                } else {
                    e.plan[i].removed = true
                }
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
