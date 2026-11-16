import FolioCore
import Foundation

public enum AssignmentStatus: String, Codable, Sendable, CaseIterable {
    // `missed`는 내지 않기로 한 과제다. 늦게 낸 과제는 상태가 아니라 제출 시각으로 안다(`Assignment.submittedAt`).
    case todo, doing, submitted, graded, missed

    public var isOpen: Bool { self == .todo || self == .doing }
}

extension AssignmentStatus {
    public var tone: StatusTone {
        switch self {
        case .submitted, .graded: .good
        case .doing: .caution
        case .todo: .muted
        case .missed: .bad
        }
    }
}
