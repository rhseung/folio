import Foundation

public struct NotionExport: Codable, Sendable {
    public struct SemesterRow: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var start: LocalDate?
        public var end: LocalDate?
    }

    public struct GradeRow: Codable, Sendable {
        public var id: UUID
        public var symbol: String
        public var points: Double?
        public var countsInCredits: Bool
    }

    public struct CodeRow: Codable, Sendable {
        public var id: UUID
        public var prefix: String
        public var department: String
        public var program: String
    }

    public struct CategoryRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var group: String
        public var parentId: UUID?
        public var minCredits: Double?
        public var maxCredits: Double?
    }

    public struct PersonRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var email: String?
        public var memo: String?
        public var role: PersonRole?
    }

    public struct ExamRow: Codable, Sendable {
        public var start: Date?
        public var end: Date?
        public var location: String?
    }

    public struct EntryRow: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var score: Double
        public var max: Double
    }

    public struct ComponentRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var weight: Double
        public var aggregation: Aggregation?
        public var expectedCount: Int?
        public var entries: [EntryRow]?
    }

    public struct CapRow: Codable, Sendable {
        public var absences: Int
        public var grade: String
    }

    public struct PolicyRow: Codable, Sendable {
        public var caps: [CapRow]?
        public var minAttendanceRatio: Double?
        public var latePolicy: String?
        public var notes: String?
    }

    public struct CourseRow: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var titleEn: String?
        public var number: String
        public var credits: Double
        public var mode: String
        public var gradeId: UUID?
        public var absoluteScore: Double?
        public var semesterId: UUID
        public var codeIds: [UUID]
        public var categoryIds: [UUID]?
        public var personIds: [UUID]?
        public var midterm: ExamRow?
        public var final: ExamRow?
        public var components: [ComponentRow]?
        public var policy: PolicyRow?
        public var memo: String?
    }

    public var semesters: [SemesterRow]
    public var grades: [GradeRow]
    public var codes: [CodeRow]
    public var categories: [CategoryRow]
    public var people: [PersonRow]
    public var courses: [CourseRow]
}
