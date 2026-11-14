import Foundation

public enum AssignmentGroup: CaseIterable, Sendable {
    case overdue, open, submitted, graded

    public init(_ a: Assignment, now: Date) {
        switch a.status {
        case .graded: self = .graded
        case .submitted: self = .submitted
        case .todo, .doing: self = (a.due.map { $0 < now } ?? false) ? .overdue : .open
        }
    }

    public func sorted(_ items: [Assignment]) -> [Assignment] {
        switch self {
        case .overdue, .open: items.sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
        case .submitted, .graded: items.sorted { ($0.due ?? .distantPast, $0.title) > ($1.due ?? .distantPast, $1.title) }
        }
    }
}
