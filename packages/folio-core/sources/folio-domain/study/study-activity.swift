import Foundation

/// Auto-recorded study time for the course screen in front (docs/SPEC.md "공부 시간"). Recording stops
/// `idleLimit` after the last input; the next input starts a new span.
public struct ActivitySpan: Sendable, Equatable {
    public static let idleLimit: TimeInterval = 5 * 60

    public private(set) var start: Date
    public private(set) var lastInput: Date

    public init(start: Date) {
        self.start = start
        self.lastInput = start
    }

    /// Returns the finished span when the user had been idle past the limit.
    public mutating func input(at date: Date) -> DateInterval? {
        defer { lastInput = date }
        guard date.timeIntervalSince(lastInput) > Self.idleLimit else { return nil }
        let done = DateInterval(start: start, end: lastInput + Self.idleLimit)
        start = date
        return done
    }

    /// The span when the screen closes or the app leaves the front at `date`.
    public func end(at date: Date) -> DateInterval {
        DateInterval(start: start, end: max(start, min(date, lastInput + Self.idleLimit)))
    }
}
