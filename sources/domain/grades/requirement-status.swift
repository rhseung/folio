import Foundation

public struct RequirementStatus: Sendable, Equatable {
    public var countsCourses: Bool
    public var done: Double
    public var taking: Double
    public var goal: Double?
    public var met: Bool
    public var over: Bool

    public init(category: Category, credits: CategoryCredits) {
        countsCourses = category.minCount != nil
        done = countsCourses ? Double(credits.passed) : credits.earned
        taking = countsCourses ? Double(credits.taking) : credits.inProgress
        goal = category.minCount.map(Double.init) ?? category.minCredits.flatMap { $0 > 0 ? $0 : nil }
        met =
            goal != nil
            && (category.minCredits.map { credits.earned >= $0 } ?? true)
            && (category.minCount.map { credits.passed >= $0 } ?? true)
        over = category.maxCredits.map { $0 > 0 && credits.earned > $0 } ?? false
    }
}
