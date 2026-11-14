import FolioDomain
import FolioStorage
import Foundation

@Action(
    "score rm", "점수 지우기", effect: .removes, confirm: "점수 '{score}'을(를) 지웁니다.", done: "점수 '{score}'을(를) 지웠습니다",
    examples: ["folio score rm EC4207/HW1 --dry-run"], phrases: ["점수 삭제"])
public struct ScoreRemove {
    @Arg var course: Course.ID
    /// 점수 제목
    @Arg var score: ScoreEntry.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { try $0.remove(ScoreEntry.self, score) }
    }
}
