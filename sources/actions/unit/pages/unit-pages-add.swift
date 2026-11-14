import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit pages add", "단원에 렉처 파일의 쪽 구간 더하기. 한 단원이 여러 파일에, 한 파일이 여러 단원에 걸칠 수 있다",
    done: "단원 '{unit}'에 {material}의 쪽 구간을 더했습니다",
    examples: ["folio unit pages add EC4207/매칭 05_Matchings.pdf --first 1 --last 4"],
    phrases: ["렉처 목차", "단원 쪽 구간", "이 단원은 몇 쪽부터"])
public struct UnitPagesAdd {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 렉처 자료
    @Arg var material: Material.ID
    /// 첫 쪽
    var first: Int
    /// 끝 쪽
    var last: Int

    public func run(_ ctx: ActionContext) throws {
        try checkPages(first, last)
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try f.update(\.units, unit) { u in
                u.lecturePages.append(UnitPages(materialId: material, firstPage: first, lastPage: last))
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
