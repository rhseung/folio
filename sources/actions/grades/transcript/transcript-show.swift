import FolioDomain
import Foundation

@Query(
    "transcript show", "한 학기의 과목, 성적, 학기 GPA", discussion: "학기를 생략하면 이번 학기.",
    examples: ["folio transcript show", "folio transcript show 2026-1"], phrases: ["이번 학기 성적", "학기 성적표"], grades: true)
public struct TranscriptShow {
    /// 학기. 폴더 이름(2026-1) 또는 '2026 봄'
    @Arg public var semester: Semester.ID?

    public struct Shown: Encodable {
        public var courses: [TranscriptRow]
        public var totalCredits: Double
        public var effectiveCredits: Double
        public var gpa: Double?
        // 사람용 출력의 머리에만 쓴다.
        public var name: String
    }

    public func read(_ ctx: ReadContext) throws -> Shown {
        let s: Semester
        if let semester {
            guard let found = try ctx.semesters().first(where: { $0.id == semester }) else {
                throw ActionError.notFound(String(localized: .errorNotFoundSemester))
            }
            s = found
        } else {
            s = try ctx.currentSemester()
        }
        let summary = GPACalculator.semester(s, courses: try ctx.allCourses(), catalog: try ctx.catalog())
        return Shown(
            courses: try TranscriptRow.rows(ctx, in: [s]), totalCredits: summary.totalCredits, effectiveCredits: summary.effectiveCredits,
            gpa: summary.gpa, name: GPAShow.name(of: s))
    }
}

extension TranscriptShow.Shown {
    private enum CodingKeys: String, CodingKey { case courses, totalCredits, effectiveCredits, gpa }
}
