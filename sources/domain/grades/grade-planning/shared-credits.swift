import Foundation

public struct SharedCredits: Sendable, Equatable {
    public var categoryId: UUID
    public var cap: Double
    public var courses: [Course]
    public var earned: Double
    public var inProgress: Double
    public var unallowed: [Course] = []
    public var excessEarned: Double { Swift.max(0, earned - cap) + unallowed.filter { $0.finalGrade != nil }.map(\.credits).reduce(0, +) }
    public var excessInProgress: Double {
        Swift.max(0, earned + inProgress - cap) - Swift.max(0, earned - cap)
            + unallowed.filter { $0.finalGrade == nil }.map(\.credits).reduce(0, +)
    }
    public var isOver: Bool { earned + inProgress > cap }
}
