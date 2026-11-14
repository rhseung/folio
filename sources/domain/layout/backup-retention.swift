import Foundation

public enum BackupRetention {
    public static func keep(_ days: [LocalDate], today: LocalDate, dailyDays: Int, calendar: Calendar) -> Set<LocalDate> {
        var kept = Set(days.filter { $0.days(until: today) < dailyDays })
        var newestPerWeek: [DateComponents: LocalDate] = [:]
        for day in days where !kept.contains(day) {
            let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day.date(in: calendar)!)
            newestPerWeek[week] = max(newestPerWeek[week] ?? day, day)
        }
        kept.formUnion(newestPerWeek.values)
        return kept
    }
}
