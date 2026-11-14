import FolioDomain
import Foundation

public struct GradingPolicyExtraction: StructuredResult, Equatable {
    public struct Component: Codable, Sendable, Equatable {
        public var name: String
        public var weight: Double
        public var aggregation: String
        public var expectedCount: Int?
    }

    public struct Cap: Codable, Sendable, Equatable {
        public var absences: Int
        public var maxGrade: String
    }

    public var components: [Component]
    public var attendanceCaps: [Cap]
    public var minAttendanceRatio: Double?
    public var latePolicy: String?
    public var notes: String

    public static let schema = Schema.object([
        "components": Schema.array(
            Schema.object([
                "name": Schema.string, "weight": Schema.number, "aggregation": Schema.string,
                "expectedCount": Schema.nullable(Schema.integer),
            ])),
        "attendanceCaps": Schema.array(Schema.object(["absences": Schema.integer, "maxGrade": Schema.string])),
        "minAttendanceRatio": Schema.nullable(Schema.number),
        "latePolicy": Schema.nullable(Schema.string),
        "notes": Schema.string,
    ])
}
