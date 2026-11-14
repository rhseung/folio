import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit pages set", "단원의 렉처 쪽 구간 고치기. 그 파일에서 단원이 가진 구간을 이 구간 하나로 바꾼다",
    done: "단원 '{unit}'의 {material} 쪽 구간을 고쳤습니다",
    examples: ["folio unit pages set EC4207/매칭 05_Matchings.pdf --first 1 --last 6"],
    phrases: ["단원 쪽 구간 고치기", "목차 경계 옮기기"])
public struct UnitPagesSet {
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
                let next =
                    u.lecturePages.filter { $0.materialId != material } + [
                        UnitPages(materialId: material, firstPage: first, lastPage: last)
                    ]
                guard next != u.lecturePages else { return }
                u.lecturePages = next
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
