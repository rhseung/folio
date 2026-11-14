import FolioDomain
import Foundation

@Query(
    "course list", "과목 목록. 생략하면 현재 학기",
    examples: ["folio course list", "folio course list --semester 2026-1", "folio course list --all --lines"],
    phrases: ["과목 목록", "수강 과목"], panel: true, lines: true)
public struct CourseList {
    /// 학기
    public var semester: Semester.ID?
    /// 모든 학기
    public var all = false

    public func read(_ ctx: ReadContext) throws -> [Course] {
        let id = all ? nil : try semester ?? ctx.currentSemester().id
        return ctx.courses().map(\.file.course).filter { id == nil || $0.semesterId == id }
    }
}
