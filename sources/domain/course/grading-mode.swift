import Foundation

public enum GradingMode: String, Codable, Sendable, CaseIterable {
    case relative
    case absolute
    case passFail = "pass_fail"
}
