import Foundation

// 시각과 길이를 숫자로 적는 형식이다. 파일 이름, 링크의 `#t=`, CLI 출력이 같은 형식을 써야 서로 읽을 수 있다.
public enum ClockText {
    // 한 시간이 안 되면 `m:ss`, 넘으면 `h:mm:ss`다.
    public static func duration(_ seconds: Int, hours: Bool = false) -> String {
        let s = max(seconds, 0)
        return hours || s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    // 자정부터 센 분을 `HH:mm`으로 쓴다.
    public static func minute(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    public static func range(_ start: Int, _ end: Int) -> String { minute(start) + "–" + minute(end) }
}

extension Calendar {
    public func minuteOfDay(_ date: Date) -> Int { component(.hour, from: date) * 60 + component(.minute, from: date) }

    // 그날 자정부터 센 분의 시각이다. 서머타임이 있는 날에도 벽시계 시각을 맞춘다.
    public func date(atMinute minute: Int, of day: Date) -> Date? {
        date(bySettingHour: minute / 60 % 24, minute: minute % 60, second: 0, of: day)
    }
}
