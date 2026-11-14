import FolioDomain
import Foundation

@Query(
    "gpa", "학기별 학점과 GPA, 누적과 전공", examples: ["folio gpa", "folio gpa --json"], phrases: ["평점", "학점 평균", "누적 학점"],
    grades: true)
public struct GPAShow {
    public struct Row: Encodable {
        public var name: String
        public var totalCredits: Double
        public var effectiveCredits: Double
        public var gpa: Double?
    }

    // 학기마다 한 줄, 그 뒤에 누적과 전공 두 줄이다.
    public func read(_ ctx: ReadContext) throws -> [Row] {
        let catalog = try ctx.catalog()
        let courses = try ctx.allCourses()
        let semesters = try ctx.semesters()
        let row = { (name: String, s: GPACalculator.Summary) in
            Row(name: name, totalCredits: s.totalCredits, effectiveCredits: s.effectiveCredits, gpa: s.gpa)
        }
        return semesters.map { row(Self.name(of: $0), GPACalculator.semester($0, courses: courses, catalog: catalog)) } + [
            row(String(localized: .gpaCumulative), GPACalculator.cumulative(semesters: semesters, courses: courses, catalog: catalog)),
            row(String(localized: .gpaMajor), GPACalculator.major(courses: courses, catalog: catalog)),
        ]
    }

    public static func name(of s: Semester) -> String { s.folder?.name ?? s.source ?? String(localized: .semesterRecognized) }
}
