import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material untrack", "자료 추적 그만두기. 파일은 그대로 두고 회차, 문제 묶음, 과제의 연결은 푼다", done: "자료 '{material}'의 추적을 그만뒀습니다",
    examples: ["folio material untrack EC4207/Seating.pdf"], phrases: ["추적 그만", "자료 목록에서 빼기"])
public struct MaterialUntrack {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try f.remove(Material.self, material)
        }
    }
}
