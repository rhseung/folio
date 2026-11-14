import FolioDomain
import Foundation

@Query(
    "requirement show", "졸업 요건과 학생 정보 보기", examples: ["folio requirement show"],
    phrases: ["졸업 요건", "졸업까지 남은 학점", "이수 현황"])
public struct RequirementShow {
    public func read(_ ctx: ReadContext) throws -> GraduationRule { try ctx.transcript().graduation }
}
