import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan rm", "공부 계획 항목 지우기", effect: .removes, confirm: "공부 계획 항목 '{item}'을(를) 지웁니다.",
    done: "공부 계획에서 '{item}'을(를) 지웠습니다", examples: [#"folio exam plan rm EC4207/중간고사 "트리 단원 복습" --dry-run"#])
public struct ExamPlanRemove {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 항목 제목이나 UUID
    @Arg var item: ExamPlanItem.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard e.plan.contains(where: { $0.id == item }) else {
                    throw ActionError.notFound(String(localized: .errorNotFoundPlanItem))
                }
                e.plan.removeAll { $0.id == item }
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
