import FolioDomain
import Foundation

extension Workspace {
    var today: LocalDate { settings.studyDay(of: now, calendar: calendar) }

    /// Whether `date` falls on today's study day: a class at 23:00 is still "today" at 01:00, before the day boundary.
    func isStudyToday(_ date: Date) -> Bool { settings.studyDay(of: date, calendar: calendar) == today }

    /// Study days from today to `date`, so a D-day doesn't jump at midnight while the day boundary is still ahead.
    func days(to date: Date) -> Int { today.days(until: LocalDate(date, in: calendar)) }
}
