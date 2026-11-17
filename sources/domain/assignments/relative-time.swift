import Foundation

public enum RelativeTime {
    // 하루 안의 남은 시간이나 지난 시간을 시간 단위로, 한 시간 안이면 분 단위로 쓴다. 하루를 넘으면 nil이고
    // 그때는 공부일로 센 상대 날짜를 쓴다. 단위보다 작은 나머지는 버려서, 59분 남으면 "59분 뒤"이지 "1시간 뒤"가 아니다.
    public static func text(until date: Date, from now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        let minutes = Int((abs(seconds) / 60).rounded(.down))
        guard minutes < 24 * 60 else { return nil }
        let later = seconds > 0
        if minutes >= 60 {
            let hours = minutes / 60
            return later ? String(localized: .relativeTimeHoursLater(hours)) : String(localized: .relativeTimeHoursAgo(hours))
        }
        if minutes == 0 { return String(localized: .relativeTimeNow) }
        return later ? String(localized: .relativeTimeMinutesLater(minutes)) : String(localized: .relativeTimeMinutesAgo(minutes))
    }
}
