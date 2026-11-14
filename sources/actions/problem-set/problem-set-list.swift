import FolioDomain
import Foundation

@Query(
    "problem-set list", "과목의 문제 묶음", examples: ["folio problem-set list EC4207"], phrases: ["문제 목록", "연습 문제"], panel: true,
    lines: true)
public struct ProblemSetList {
    /// 과목
    @Arg public var course: Course.ID

    public func read(_ ctx: ReadContext) throws -> [ProblemSet] { try ctx.file(course).problemSets }
}
