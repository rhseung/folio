import FolioDomain
import Foundation

@Query("unit show", "단원 하나의 자세한 내용", examples: ["folio unit show EC4207/트리"], phrases: ["단원 보기"], panel: true)
public struct UnitShow {
    @Arg public var course: Course.ID
    /// 단원
    @Arg public var unit: FolioDomain.Unit.ID

    public func read(_ ctx: ReadContext) throws -> FolioDomain.Unit {
        guard let found = try ctx.file(course).units.first(where: { $0.id == unit }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundUnit))
        }
        return found
    }
}
