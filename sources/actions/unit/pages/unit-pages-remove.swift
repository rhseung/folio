import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit pages rm", "단원에서 렉처 파일의 쪽 구간 빼기. 파일과 단원은 그대로 둔다", effect: .removes,
    confirm: "단원 '{unit}'에서 {material}의 쪽 구간을 뺍니다.", done: "단원 '{unit}'에서 {material}의 쪽 구간을 뺐습니다",
    examples: ["folio unit pages rm EC4207/매칭 05_Matchings.pdf --dry-run"], phrases: ["단원 쪽 구간 지우기"])
public struct UnitPagesRemove {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 렉처 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try f.update(\.units, unit) { u in
                guard u.lecturePages.contains(where: { $0.materialId == material }) else { return }
                u.lecturePages.removeAll { $0.materialId == material }
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
