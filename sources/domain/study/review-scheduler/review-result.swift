import Foundation

public enum ReviewResult: String, Codable, Sendable, CaseIterable {
    case again, hard, good, easy
    case skip
}

extension ReviewResult {
    public var tone: StatusTone {
        switch self {
        case .good, .easy: .good
        case .hard: .caution
        case .again: .bad
        case .skip: .plain
        }
    }
}
