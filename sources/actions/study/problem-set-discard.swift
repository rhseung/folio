import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem-set discard", "자료에서 뽑은 문제 제안을 버리기", discussion: "과목에는 아무것도 남지 않는다. 다시 뽑으면 새 제안이 생긴다.",
    effect: .removes, confirm: "{material}에서 뽑은 문제 제안을 버립니다.", done: "{material}에서 뽑은 문제 제안을 버렸습니다",
    examples: [#"folio problem-set discard "EC4207/2024 Midterm.pdf""#], phrases: ["문제 제안 버리기"])
public struct ProblemSetDiscard {
    @Arg var course: Course.ID
    /// 문제지 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.discardDraft(course, try ctx.requireProblemDraft(course, material: material).id)
    }
}
