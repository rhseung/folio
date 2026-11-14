import FolioDomain
import Foundation

public struct FileClassification: StructuredResult, Equatable {
    public var role: String
    public var kind: String
    public var suggestedPath: String
    public var week: Int?
    public var assignmentTitle: String?
    public var confident: Bool
    public var reason: String

    public static let schema = Schema.object([
        "role": Schema.enumeration(MaterialRole.allCases.map(\.rawValue)),
        "kind": Schema.enumeration(["problem", "solution", "submission", "slides", "book", "syllabus", "other"]),
        "suggestedPath": Schema.string,
        "week": Schema.nullable(Schema.integer),
        "assignmentTitle": Schema.nullable(Schema.string),
        "confident": .object(["type": .string("boolean")]),
        "reason": Schema.string,
    ])
}
