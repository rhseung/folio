import Foundation

public enum DDay {
    // 지난 날은 쓰지 않는다. 시험과 마감 표시는 지나면 사라지기 때문이다.
    public static func text(_ days: Int) -> String {
        days == 0 ? String(localized: .ddayToday) : String(localized: .ddayDays(max(days, 0)))
    }
}
