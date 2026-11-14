import FolioDomain
import Foundation

@Query(
    "course show", "과목 하나의 자세한 내용", examples: ["folio course show EC4207"], phrases: ["과목 정보", "과목 시간표"],
    panel: true)
public struct CourseShow {
    /// 과목
    @Arg public var course: Course.ID

    public func read(_ ctx: ReadContext) throws -> Course { try ctx.file(course).course }
}
