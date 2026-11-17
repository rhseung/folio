import Foundation

public enum RelativeDay {
    // 공부일로 센 날 수를 말로 쓴다. 0은 오늘이고 음수는 지난 날이다. 7일부터는 주, 30일부터는 달로 세고
    // 단위보다 작은 나머지는 버린다. 13일은 "1주 뒤"이고, 달은 달력의 길이와 상관없이 30일이다.
    public static let week = 7
    public static let month = 30

    public static func text(_ days: Int) -> String {
        let later = days > 0
        let count = abs(days)
        switch count {
        case 0: return String(localized: .relativeDayToday)
        case 1: return later ? String(localized: .relativeDayTomorrow) : String(localized: .relativeDayYesterday)
        case ..<week: return later ? String(localized: .relativeDayLater(count)) : String(localized: .relativeDayAgo(count))
        case ..<month:
            return later ? String(localized: .relativeDayWeeksLater(count / week)) : String(localized: .relativeDayWeeksAgo(count / week))
        default:
            return later
                ? String(localized: .relativeDayMonthsLater(count / month)) : String(localized: .relativeDayMonthsAgo(count / month))
        }
    }
}
