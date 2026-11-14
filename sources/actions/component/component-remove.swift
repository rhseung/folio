import FolioDomain
import FolioStorage
import Foundation

@Action(
    "component rm", "성적 항목과 그 점수 지우기. 과제와 시험은 남고 연결만 풀린다", effect: .removes,
    confirm: "성적 항목 '{component}'과(와) 그 점수를 지웁니다. 과제와 시험은 남습니다.", done: "성적 항목 '{component}'을(를) 지웠습니다",
    examples: ["folio component rm EC4207/퀴즈 --dry-run"], phrases: ["평가 항목 삭제"])
public struct ComponentRemove {
    @Arg var course: Course.ID
    /// 항목 이름
    @Arg var component: GradeComponent.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(component, in: f.components, .valueComponent)
            try f.remove(GradeComponent.self, component)
        }
    }
}
