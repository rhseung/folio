import FolioDomain
import Foundation

@Query(
    "exam show", "시험 하나의 자세한 내용: 범위 단원, 공부 계획", examples: ["folio exam show EC4207/중간고사"],
    phrases: ["몇 시", "어디서", "시험 장소 보기", "시험 범위 보기", "시험 정보", "시험 시간과 장소"], panel: true)
public struct ExamShow {
    @Arg public var course: Course.ID
    /// 시험
    @Arg public var exam: Exam.ID

    public func read(_ ctx: ReadContext) throws -> QueryLinks<Exam> {
        let f = try ctx.file(course)
        guard let found = f.exams.first(where: { $0.id == exam }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundExam))
        }
        return QueryLinks(found, in: f)
    }
}
