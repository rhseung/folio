import FolioDomain
import Foundation

@Query(
    "assignment show", "과제 하나의 자세한 내용과 점수", examples: ["folio assignment show EC4207/HW3"],
    phrases: ["과제 자세히", "과제 마감 언제", "과제 점수"], panel: true)
public struct AssignmentShow {
    @Arg public var course: Course.ID
    /// 과제
    @Arg public var assignment: Assignment.ID

    public func read(_ ctx: ReadContext) throws -> Assignment {
        guard let found = try ctx.file(course).assignments.first(where: { $0.id == assignment }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(ItemKind.assignment.noun)))
        }
        return found
    }
}
