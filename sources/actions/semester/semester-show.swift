import FolioDomain
import Foundation

@Query(
    "semester show", "학기 하나. 생략하면 현재 학기", examples: ["folio semester show", "folio semester show 2026-1"],
    phrases: ["이번 학기 정보", "개강일"])
public struct SemesterShow {
    /// 학기. 2026-3 또는 "2026 fall". 생략하면 현재 학기
    @Arg public var semester: Semester.ID?

    public func read(_ ctx: ReadContext) throws -> Semester {
        let semesters = try ctx.transcript().semesters
        if let semester {
            guard let found = semesters.first(where: { $0.id == semester }) else {
                throw ActionError.notFound(String(localized: .errorNotFoundSemester))
            }
            return found
        }
        guard let current = semesters.current(on: ctx.today) else { throw ActionError.notFound(String(localized: .errorNoSemester)) }
        return current
    }
}
