import FolioDomain
import Foundation

@Query("semester list", "학기 목록", examples: ["folio semester list"], phrases: ["학기 목록"], lines: true)
public struct SemesterList {
    public func read(_ ctx: ReadContext) throws -> [Semester] { (try? ctx.semesters()) ?? [] }
}
