import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan-check", "공부 계획 항목 끝내기, --undo면 되돌리기", effect: .logs, done: "공부 계획 항목 '{item}'을(를) 표시했습니다",
    cli: .manual(reason: "항목을 <과목>/<시험> 안에서 찾지만 액션은 시험을 받지 않고, --undo면 완료 문구가 달라진다"))
public struct ExamPlanCheck {
    @Arg var course: Course.ID
    @Arg var item: ExamPlanItem.ID
    @Off("undo") var done = true

    public func run(_ ctx: ActionContext) throws {
        guard try ctx.file(course).exams.contains(where: { $0.plan.contains { $0.id == item } }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundPlanItem))
        }
        try ctx.log(PlanCheckEvent(itemId: item, done: done), course: course)
    }
}
