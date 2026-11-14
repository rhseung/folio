import Foundation

public enum AssignmentStatus: String, Codable, Sendable, CaseIterable {
    case todo, doing, submitted, graded

    public var isOpen: Bool { self == .todo || self == .doing }
}

extension AssignmentStatus {
    public var tone: StatusTone {
        switch self {
        case .submitted, .graded: .good
        case .doing: .caution
        case .todo: .muted
        }
    }
}
