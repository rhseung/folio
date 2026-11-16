import FolioCore
import Foundation

public enum GradingMode: String, Codable, Sendable, CaseIterable {
    case relative
    case absolute
    case passFail = "pass_fail"
}

extension GradingMode {
    public var tone: StatusTone {
        switch self {
        case .relative, .absolute: .plain
        case .passFail: .muted
        }
    }
}
