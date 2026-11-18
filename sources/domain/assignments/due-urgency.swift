import Foundation

public enum DueUrgency: Int, Comparable, Sendable {
    case urgent, soon, later

    public init(studyDays days: Int, settings: UrgencySettings) {
        self = days <= settings.assignmentUrgentDays ? .urgent : days < settings.assignmentSoonDays ? .soon : .later
    }

    public init(due: Date, now: Date, settings: Settings, calendar: Calendar) {
        self.init(studyDays: RelativeDate.days(due, from: now, settings: settings, calendar: calendar), settings: settings.urgency)
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
