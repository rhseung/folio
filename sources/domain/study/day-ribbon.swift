import Foundation

/// The hours Today's day ribbon spans, in whole hours from the study day's midnight: an hour before the first class to
/// an hour after the last, so a light day's blocks are wide enough to read. A day without classes spans 9 to midnight.
public struct DayRibbon: Sendable, Equatable {
    public var midnight: Date
    public var startHour: Int
    public var endHour: Int

    public init(day: LocalDate, classes: [DateInterval], calendar: Calendar, margin: Int = 1) {
        let midnight = day.date(in: calendar) ?? .distantPast
        self.midnight = midnight
        let starts = classes.map { $0.start.timeIntervalSince(midnight) / 3600 }
        let ends = classes.map { $0.end.timeIntervalSince(midnight) / 3600 }
        self.startHour = starts.min().map { max(0, Int($0.rounded(.down)) - margin) } ?? 9
        self.endHour = ends.max().map { Int($0.rounded(.up)) + margin } ?? 24
    }

    /// Where `date` falls, 0 at the start hour and 1 at the end, held to the ribbon: a 1am deadline sits at its edge.
    public func position(of date: Date) -> Double {
        let hours = date.timeIntervalSince(midnight) / 3600
        return min(1, max(0, (hours - Double(startHour)) / Double(endHour - startHour)))
    }

    public func contains(_ date: Date) -> Bool {
        let hours = date.timeIntervalSince(midnight) / 3600
        return hours >= Double(startHour) && hours <= Double(endHour)
    }

    /// Hours on the clock (9, 12, 15 …) rather than offsets from the start, closer together on a shorter span so it
    /// still gets a few.
    public var ticks: [Int] {
        let span = endHour - startHour
        let step = span <= 6 ? 1 : span <= 12 ? 2 : 3
        return (startHour...endHour).filter { $0 % step == 0 }
    }
}
