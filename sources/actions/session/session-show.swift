import FolioDomain
import Foundation

@Query(
    "session show", "회차 하나의 자세한 내용", examples: ["folio session show EC4207/10-26"], phrases: ["수업 하나 보기", "회차 자세히"],
    panel: true)
public struct SessionShow {
    @Arg public var course: Course.ID
    /// 회차
    @Arg public var session: Session.ID

    public func read(_ ctx: ReadContext) throws -> Session {
        guard let s = try ctx.file(course).sessions.first(where: { $0.id == session }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(ItemKind.session.noun)))
        }
        return s
    }
}
