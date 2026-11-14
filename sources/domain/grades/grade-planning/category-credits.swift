import Foundation

public struct CategoryCredits: Sendable, Equatable {
    public var earned: Double = 0
    public var inProgress: Double = 0
    public var passed = 0
    public var taking = 0

    public init(earned: Double = 0, inProgress: Double = 0, passed: Int = 0, taking: Int = 0) {
        self.earned = earned
        self.inProgress = inProgress
        self.passed = passed
        self.taking = taking
    }
}
