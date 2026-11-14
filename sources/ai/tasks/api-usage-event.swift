import FolioDomain
import Foundation

public struct APIUsageEvent: LogEvent, Equatable {
    public static let type = "api_usage"
    public var task: ClaudeTask
    public var model: String
    public var usage: Usage

    public var cost: Double? { ModelPricing.table[model]?.cost(of: usage) }
}
