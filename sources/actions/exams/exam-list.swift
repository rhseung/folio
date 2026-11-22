import FolioDomain
import Foundation

@Query(
    "exam list", "과목의 시험 목록", examples: ["folio exam list EC4207", "folio exam list EC4207 --lines"],
    phrases: ["시험 목록", "시험 언제"], panel: true, lines: true)
public struct ExamList {
    /// 과목. 강의 코드, 폴더 이름, 과목 이름, UUID
    @Arg public var course: Course.ID

    public func read(_ ctx: ReadContext) throws -> [QueryLinks<Exam>] {
        let f = try ctx.file(course)
        return f.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }.map { QueryLinks($0, in: f) }
    }
}
