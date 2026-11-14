import FolioDomain
import Foundation

public struct AssignmentExtraction: StructuredResult, Equatable {
    public var title: String
    public var due: String?

    public static let schema = Schema.object(["title": Schema.string, "due": Schema.nullable(Schema.string)])
}
