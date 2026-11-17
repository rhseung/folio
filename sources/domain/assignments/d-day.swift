import Foundation

public enum DDay {
    // 지난 날은 쓰지 않는다. 시험과 마감 표시는 지나면 사라지기 때문이다.
    public static func text(_ days: Int) -> String {
        days == 0 ? String(localized: .ddayToday) : String(localized: .ddayDays(max(days, 0)))
    }

    // 과제 칩은 지난 마감도 보인다. 음수는 마감이 지난 날 수다.
    public static func signed(_ days: Int) -> String {
        days < 0 ? String(localized: .ddayAfter(-days)) : text(days)
    }

    // 지난 마감은 지각 셈(`LateRule.lateDays`)과 같은 날 수를 음수로 준다. 달력으로 세면 "D+1"과 늦게 낸 날 수가 어긋난다.
    public static func days(to due: Date, from now: Date, calendar: Calendar) -> Int {
        if due < now { return -LateRule.lateDays(due: due, at: now) }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
    }
}
