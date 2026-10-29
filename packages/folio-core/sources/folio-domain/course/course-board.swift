import Foundation

extension Exam {
    /// Over once it has ended, not when the day turns: an exam that finished this morning is no longer coming.
    public func isOver(now: Date, today: LocalDate, calendar: Calendar) -> Bool {
        if let end { return end < now }
        return start.map { LocalDate($0, in: calendar) < today } ?? false
    }
}

/// The assignments page's groups, in the order they are shown.
public enum AssignmentGroup: CaseIterable, Sendable {
    case overdue, open, submitted, graded

    public init(_ a: Assignment, now: Date) {
        switch a.status {
        case .graded: self = .graded
        case .submitted: self = .submitted
        case .todo, .doing: self = (a.due.map { $0 < now } ?? false) ? .overdue : .open
        }
    }

    /// Work still to do by the nearest deadline; finished work by the latest first.
    public func sorted(_ items: [Assignment]) -> [Assignment] {
        switch self {
        case .overdue, .open: items.sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
        case .submitted, .graded: items.sorted { ($0.due ?? .distantPast, $0.title) > ($1.due ?? .distantPast, $1.title) }
        }
    }
}

extension CourseFile {
    /// The session pointing at a note is the one the sessions page shows it under, whatever its frontmatter says.
    public func session(pointingAt note: UUID?) -> Session? {
        guard let note else { return nil }
        return sessions.first { $0.roughNoteId == note || $0.reviewNoteId == note }
    }

    /// A note's session: the one pointing at it, else the one its frontmatter names.
    public func session(of meta: NoteMeta) -> Session? {
        session(pointingAt: meta.id) ?? meta.sessionId.flatMap { id in sessions.first { $0.id == id } }
    }
}

extension ReviewState {
    /// A state exists as soon as a class covered the unit, so having one says nothing about reviewing it.
    public func isOnTrack(today: LocalDate) -> Bool {
        !writeNoteFirst && (due.map { $0 >= today } ?? true)
    }
}
