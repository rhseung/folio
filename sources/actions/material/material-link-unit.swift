import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material link-unit", "자료를 단원에 연결하거나 떼기", done: "자료 '{material}'과(와) 단원 '{unit}'의 연결을 바꿨습니다",
    examples: ["folio material link-unit EC4207/05_Matchings.pdf 매칭", "folio material link-unit EC4207/05_Matchings.pdf 매칭 --off"],
    phrases: ["자료 단원 연결"])
public struct MaterialLinkUnit {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID
    /// 같은 과목의 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 연결 떼기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            _ = try index(unit, in: f.units, .valueUnit)
            f.setMaterial(material, unit: unit, linked: linked)
        }
    }
}
