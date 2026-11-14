import FolioDomain
import Foundation

@Query(
    "component list", "과목의 성적 항목과 비중", examples: ["folio component list EC4207"], phrases: ["성적 비율 보기", "평가 항목"],
    panel: true, lines: true)
public struct ComponentList {
    /// 과목
    @Arg public var course: Course.ID

    public func read(_ ctx: ReadContext) throws -> [GradeComponent] {
        try ctx.file(course).components.sorted { $0.order < $1.order }
    }
}
