import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material viewed", "자료의 한 쪽을 본 것으로 기록. 앱은 한 쪽에 오래 머물면 이것을 부른다", effect: .logs, done: "'{material}' {page}쪽을 본 것으로 기록했습니다",
    examples: [#"folio material viewed EC4207/Lectures/05_Matchings.pdf 7"#], phrases: ["슬라이드 봤", "쪽 봤음"], panel: true)
public struct MaterialViewed {
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID
    /// 쪽 번호(1부터)
    @Arg var page: Int

    public func run(_ ctx: ActionContext) throws {
        _ = try index(material, in: try ctx.file(course).materials, .valueMaterial)
        guard page >= 1 else { throw ActionError.rule(String(localized: .errorPageNumber)) }
        try ctx.log(PageViewEvent(materialId: material, page: page), course: course)
    }
}
