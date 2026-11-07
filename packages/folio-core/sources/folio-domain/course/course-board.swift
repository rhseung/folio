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
    /// A note's sessions, in date order: the sessions are the only place the link is kept. A rough note has one; a
    /// review note may cover several classes caught up on at once.
    public func sessions(pointingAt note: UUID?) -> [Session] {
        guard let note else { return [] }
        return sessions.filter { $0.roughNoteId == note || $0.reviewNoteId == note }.sorted(by: Session.inOrder)
    }

    /// `11/3(화) – 11/10(화)`: the days of the note's first and last sessions, or the one alone. Nil with none.
    public func sessionSpan(of note: UUID?, calendar: Calendar) -> String? {
        let linked = sessions(pointingAt: note)
        guard let first = linked.first, let last = linked.last else { return nil }
        let day = { (s: Session) in self.day(of: s, calendar: calendar) }
        return first.id == last.id ? day(first) : String(localized: .sessionSpan(day(first), day(last)))
    }
}

extension ReviewState {
    /// A state exists as soon as a class covered the unit, so having one says nothing about reviewing it.
    public func isOnTrack(today: LocalDate) -> Bool {
        !writeNoteFirst && (due.map { $0 >= today } ?? true)
    }
}
