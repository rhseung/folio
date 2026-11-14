import FolioDomain
import Foundation

public struct MonthlyUsage: Sendable, Equatable {
    public var year: Int
    public var month: Int
    public var requests: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var cost: Double
}
