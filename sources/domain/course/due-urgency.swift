import Foundation

public enum DueUrgency: Int, Comparable, Sendable {
    case urgent, soon, later

    public init(studyDays days: Int) {
        self = days <= 1 ? .urgent : days < 7 ? .soon : .later
    }

    public init(due: Date, now: Date, settings: Settings, calendar: Calendar) {
        self.init(studyDays: settings.studyDays(from: now, until: due, calendar: calendar))
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
