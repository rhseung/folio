import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material rm", "자료 파일을 휴지통으로 옮기고 추적에서 뺀다", discussion: "휴지통에서 되살릴 수 있다.", effect: .removes,
    confirm: "{material}을(를) 휴지통으로 옮깁니다.", done: "{material}을(를) 휴지통으로 옮겼습니다",
    examples: ["folio material rm EC4207/Seating.pdf --dry-run"], phrases: ["파일 삭제", "휴지통"])
public struct MaterialTrash {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let m = file.materials[try index(material, in: file.materials, .valueMaterial)]
        ctx.record(Change(.removed, try ctx.relative(course, m.path)))
        try ctx.edit(course) { f in
            if ctx.dryRun { try f.remove(Material.self, material) } else { try store.trash(material, in: &f) }
        }
    }
}
