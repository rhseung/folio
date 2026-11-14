import FolioDomain
import FolioStorage
import Foundation

// 명령줄에서 상태가 자료보다 앞에 오므로 먼저 선언한다.
@Action(
    "material status", "자료의 상태 바꾸기. 여러 개면 확인을 받는다", confirm: "자료 {materials}의 상태를 {status}(으)로 바꿉니다.",
    done: "자료 {materials}을(를) {status}(으)로 바꿨습니다",
    examples: ["folio material status ignored EC4207/Seating.pdf", "folio material status classified EC4207/Problems.pdf Guideline.pdf"],
    phrases: ["자료 분류", "자료 무시"])
public struct MaterialStatusSet {
    @Arg var course: Course.ID
    /// 상태
    @Arg var status: MaterialStatus
    /// 자료
    @Arg var materials: [Material.ID]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            for id in materials { _ = try index(id, in: f.materials, .valueMaterial) }
            for i in f.materials.indices where materials.contains(f.materials[i].id) { f.materials[i].status = status }
        }
    }
}
