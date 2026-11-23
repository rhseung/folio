import Foundation

public struct CollectionGrade: Sendable, Equatable {
    public var problem: UUID
    public var outcome: GradeOutcome
    public var page: Int?
}
