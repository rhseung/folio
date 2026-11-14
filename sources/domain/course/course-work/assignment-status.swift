import Foundation

public enum AssignmentStatus: String, Codable, Sendable, CaseIterable {
    case todo, doing, submitted, graded

    public var isOpen: Bool { self == .todo || self == .doing }
}
