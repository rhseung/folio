import FolioDomain
import Foundation

public struct TranscriptRow: Encodable {
    public var semester: String
    public var code: String
    public var courseId: UUID
    public var title: String
    public var credits: Double
    public var gradingMode: GradingMode
    public var grade: String?

    static func rows(_ ctx: ReadContext, in semesters: [Semester]) throws -> [TranscriptRow] {
        let catalog = try ctx.catalog()
        let courses = ctx.courses()
        return semesters.flatMap { s in
            courses.filter { $0.file.course.semesterId == s.id }.sorted { $0.code < $1.code }.map { c in
                let course = c.file.course
                return TranscriptRow(
                    semester: GPAShow.name(of: s), code: c.code, courseId: c.id, title: course.title, credits: course.credits,
                    gradingMode: course.gradingMode, grade: catalog.grade(course.finalGrade)?.symbol)
            }
        }
    }
}
