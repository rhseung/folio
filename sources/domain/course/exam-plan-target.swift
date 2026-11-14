import Foundation

public struct ExamPlanTarget: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case unit
        case problemSet = "problem_set"
        case quiz
    }

    public var kind: Kind
    public var id: UUID

    public init(kind: Kind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}
