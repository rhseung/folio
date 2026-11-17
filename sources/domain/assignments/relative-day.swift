import Foundation

public enum RelativeDay {
    // 공부일로 센 날 수를 말로 쓴다. 0은 오늘이고 음수는 지난 날이다.
    public static func text(_ days: Int) -> String {
        switch days {
        case 0: String(localized: .relativeDayToday)
        case 1: String(localized: .relativeDayTomorrow)
        case -1: String(localized: .relativeDayYesterday)
        case 2...: String(localized: .relativeDayLater(days))
        default: String(localized: .relativeDayAgo(-days))
        }
    }
}
