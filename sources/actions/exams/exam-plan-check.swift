import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan-check", "공부 계획 항목 끝내기, --undo면 되돌리기", effect: .logs, done: "공부 계획 항목 {items}을(를) 표시했습니다",
    cli: .manual(reason: "항목을 <과목>/<시험> 안에서 찾지만 액션은 시험을 받지 않고, --undo면 완료 문구가 달라진다"), panel: true)
public struct ExamPlanCheck {
    @Arg var course: Course.ID
    /// 항목. 정리 노트 한 줄의 단계를 함께 줄 수 있다
    @Arg var items: [ExamPlanItem.ID]
    @Off("undo") var done = true
    /// 앱이 풀기를 끝내며 남긴 체크
    @Hidden var auto = false

    public func run(_ ctx: ActionContext) throws {
        let known = Set(try ctx.file(course).exams.flatMap(\.plan).map(\.id))
        guard items.allSatisfy(known.contains) else { throw ActionError.notFound(String(localized: .errorNotFoundPlanItem)) }
        for item in items { try ctx.log(PlanCheckEvent(itemId: item, done: done, auto: auto), course: course) }
    }
}
