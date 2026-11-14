import Foundation

public struct ActivitySpan: Sendable, Equatable {
    public static let idleLimit: TimeInterval = 5 * 60

    public private(set) var start: Date
    public private(set) var lastInput: Date

    public init(start: Date) {
        self.start = start
        self.lastInput = start
    }

    public mutating func input(at date: Date) -> DateInterval? {
        defer { lastInput = date }
        guard date.timeIntervalSince(lastInput) > Self.idleLimit else { return nil }
        let done = DateInterval(start: start, end: lastInput + Self.idleLimit)
        start = date
        return done
    }

    public func end(at date: Date) -> DateInterval {
        DateInterval(start: start, end: max(start, min(date, lastInput + Self.idleLimit)))
    }
}
