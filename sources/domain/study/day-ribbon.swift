import Foundation

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

    public func position(of date: Date) -> Double {
        let hours = date.timeIntervalSince(midnight) / 3600
        return min(1, max(0, (hours - Double(startHour)) / Double(endHour - startHour)))
    }

    public func contains(_ date: Date) -> Bool {
        let hours = date.timeIntervalSince(midnight) / 3600
        return hours >= Double(startHour) && hours <= Double(endHour)
    }

    public var ticks: [Int] {
        let span = endHour - startHour
        let step = span <= 6 ? 1 : span <= 12 ? 2 : 3
        return (startHour...endHour).filter { $0 % step == 0 }
    }
}
