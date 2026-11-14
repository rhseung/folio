import Foundation

public enum ReviewStreak {
    public static func days(_ reviewDays: Set<LocalDate>, today: LocalDate) -> Int {
        var day = reviewDays.contains(today) ? today : today.adding(days: -1)
        var count = 0
        while reviewDays.contains(day) {
            count += 1
            day = day.adding(days: -1)
        }
        return count
    }
}
