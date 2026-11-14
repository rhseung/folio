import Foundation

public struct GradeCutoff: Codable, Sendable, Hashable {
    public var grade: UUID
    public var minScore: Double

    public init(grade: UUID, minScore: Double) {
        self.grade = grade
        self.minScore = minScore
    }
}
